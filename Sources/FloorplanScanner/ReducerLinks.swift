import SwiftSyntax

/// True for `@Reducer` types and types that conform to `Reducer`.
func isReducerDeclaration(attributes: AttributeListSyntax, inherits: [String]) -> Bool {
    let hasAttribute = attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Reducer" }
    return hasAttribute || inherits.contains { $0 == "Reducer" || $0 == "ReducerProtocol" }
}

/// Finds the child reducers a reducer type includes in its `body` (and, for enums, in its cases).
/// Names are raw: they may point at things that are not reducers. `resolveReducerLinks` filters them.
func reducerLinks(in members: MemberBlockSyntax, typeName: String, isEnum: Bool) -> [ReducerLink] {
    let finder = LinkFinder(typeName: typeName)
    finder.walk(members)
    let caseLinks = isEnum ? enumCaseLinks(members) : []
    return dedupe(finder.links + caseLinks)
}

/// Keeps only links to reducers found in the scan, so `Date()` or `UUID()` inside a body disappear.
public func resolveReducerLinks(_ files: [FileSummary]) -> [FileSummary] {
    let known = Set(files.flatMap(\.types).filter(\.isReducer).map(\.name))
    return files.map { file in
        var resolved = file
        resolved.types = file.types.map { type in
            var copy = type
            copy.composes = type.composes.filter { known.contains($0.child) }
            copy.createsStores = type.createsStores.filter(known.contains)
            return copy
        }
        return resolved
    }
}

/// One link per child; a precise link (scope, ifLet, ...) wins over a plain mention in `body`.
private func dedupe(_ links: [ReducerLink]) -> [ReducerLink] {
    var result: [ReducerLink] = []
    for link in links {
        if let index = result.firstIndex(where: { $0.child == link.child }) {
            if result[index].via == .body { result[index] = link }
        } else {
            result.append(link)
        }
    }
    return result
}

private func enumCaseLinks(_ members: MemberBlockSyntax) -> [ReducerLink] {
    members.members
        .compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
        .flatMap(\.elements)
        .flatMap { $0.parameterClause?.parameters.map { $0.type.trimmedDescription } ?? [] }
        .filter { !$0.contains("<") }
        .map { ReducerLink(child: $0, via: .enumCase) }
}

/// `ItemDetail.body` -> "ItemDetail": a reducer used through its static `body`.
private func staticBodyOwner(_ access: MemberAccessExprSyntax) -> String? {
    guard access.declName.baseName.text == "body", let base = access.base else { return nil }
    return base.trimmedDescription.first?.isUppercase == true ? base.trimmedDescription : nil
}

private final class LinkFinder: SyntaxVisitor {
    private static let chainMethods: [String: LinkKind] = ["ifLet": .ifLet, "forEach": .forEach, "ifCaseLet": .ifLet]
    private let typeName: String
    private(set) var links: [ReducerLink] = []

    init(typeName: String) {
        self.typeName = typeName
        super.init(viewMode: .sourceAccurate)
    }

    // Only `body` and helper properties that return a reducer matter. Nested types are scanned on their own.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let binding = node.bindings.first else { return .skipChildren }
        let returnsReducer = binding.typeAnnotation?.type.trimmedDescription.contains("Reducer") == true
        return binding.pattern.trimmedDescription == "body" || returnsReducer ? .visitChildren : .skipChildren
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if let owner = staticBodyOwner(node) { links.append(ReducerLink(child: owner, via: .body)) }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           let kind = Self.chainMethods[member.declName.baseName.text] {
            addChainLink(node, kind)
            if let base = member.base { walk(base) } // the rest of the chain: `Reduce { }.ifLet(...)`
            return .skipChildren
        }
        guard let name = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else { return .visitChildren }
        switch name {
        case "Scope":
            if let child = trailingClosureReducerName(node) { links.append(ReducerLink(child: child, via: .scope)) }
            return .skipChildren
        case "Reduce":
            return .skipChildren
        case "CombineReducers":
            return .visitChildren // only a container: its children are the links
        default:
            if name.first?.isUppercase == true { links.append(ReducerLink(child: name, via: .body)) }
            return .visitChildren
        }
    }

    private func addChainLink(_ call: FunctionCallExprSyntax, _ kind: LinkKind) {
        if let child = trailingClosureReducerName(call) {
            links.append(ReducerLink(child: child, via: kind))
        } else if let key = call.arguments.first?.expression.as(KeyPathExprSyntax.self) {
            // `.ifLet(\.$destination, action: ...)` with no closure: the child is the nested `Destination` enum.
            let word = key.trimmedDescription.filter { $0.isLetter || $0.isNumber }
            links.append(ReducerLink(child: "\(typeName).\(word.prefix(1).uppercased())\(word.dropFirst())", via: kind))
        }
    }
}

/// `{ Child() }` -> "Child". `{ Reduce(Child()) }` and `{ Child.body }` -> "Child". An inline `Reduce { }` has no child.
func trailingClosureReducerName(_ call: FunctionCallExprSyntax) -> String? {
    let item = call.trailingClosure?.statements.first?.item
    if let name = item?.as(MemberAccessExprSyntax.self).flatMap(staticBodyOwner) { return name }
    guard let first = item?.as(FunctionCallExprSyntax.self) else { return nil }
    let name = first.calledExpression.trimmedDescription
    guard name == "Reduce" else { return name }
    return first.arguments.first?.expression.as(FunctionCallExprSyntax.self)?.calledExpression.trimmedDescription
}
