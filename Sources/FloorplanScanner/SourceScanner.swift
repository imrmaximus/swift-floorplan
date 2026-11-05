import SwiftParser
import SwiftSyntax

/// Parses one Swift source string and lists its imports and type declarations.
public func scanSource(_ source: String, path: String) -> FileSummary {
    let tree = Parser.parse(source: source)
    let collector = Collector(converter: SourceLocationConverter(fileName: path, tree: tree))
    collector.walk(tree)
    return FileSummary(path: path, imports: collector.imports.sorted(), types: collector.makeTypes())
}

private final class Collector: SyntaxVisitor {
    private struct Draft {
        let name: String
        let kind: TypeKind
        let line: Int
        let inherits: [String]
        let isReducer: Bool
        let composes: [ReducerLink]
        var references: Set<String> = []
        var createsStores: Set<String> = []
    }

    private let converter: SourceLocationConverter
    private var drafts: [Draft] = []
    /// Indices into `drafts` of the types we are currently inside; the last one is the innermost.
    private var openTypes: [Int] = []
    private(set) var imports: Set<String> = []

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    func makeTypes() -> [TypeInfo] {
        drafts.map {
            TypeInfo(
                name: $0.name, kind: $0.kind, line: $0.line, inherits: $0.inherits,
                references: $0.references.sorted(), isReducer: $0.isReducer, composes: $0.composes,
                createsStores: $0.createsStores.sorted()
            )
        }
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        if let module = node.path.first?.name.text { imports.insert(module) }
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        open(node, .struct, node.name.text, node.inheritanceClause, node.attributes, node.memberBlock)
    }
    override func visitPost(_ node: StructDeclSyntax) { openTypes.removeLast() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        open(node, .class, node.name.text, node.inheritanceClause, node.attributes, node.memberBlock)
    }
    override func visitPost(_ node: ClassDeclSyntax) { openTypes.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        open(node, .enum, node.name.text, node.inheritanceClause, node.attributes, node.memberBlock)
    }
    override func visitPost(_ node: EnumDeclSyntax) { openTypes.removeLast() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        open(node, .protocol, node.name.text, node.inheritanceClause, node.attributes, node.memberBlock)
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { openTypes.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        open(node, .actor, node.name.text, node.inheritanceClause, node.attributes, node.memberBlock)
    }
    override func visitPost(_ node: ActorDeclSyntax) { openTypes.removeLast() }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        addReference(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        addReference(node.baseName.text)
        return .visitChildren
    }

    // `Store(initialState: ...) { Feature() }` marks the innermost type as the owner of that store.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let index = openTypes.last,
           node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Store",
           let reducer = trailingClosureReducerName(node) {
            drafts[index].createsStores.insert(reducer)
        }
        return .visitChildren
    }

    private func open(
        _ node: some SyntaxProtocol, _ kind: TypeKind, _ simpleName: String, _ clause: InheritanceClauseSyntax?,
        _ attributes: AttributeListSyntax, _ members: MemberBlockSyntax
    ) -> SyntaxVisitorContinueKind {
        let parent = openTypes.last.map { drafts[$0].name + "." } ?? ""
        let name = parent + simpleName
        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        let inherits = clause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let isReducer = isReducerDeclaration(attributes: attributes, inherits: inherits)
        let composes = isReducer ? reducerLinks(in: members, typeName: name, isEnum: kind == .enum) : []
        drafts.append(Draft(name: name, kind: kind, line: line, inherits: inherits, isReducer: isReducer, composes: composes))
        openTypes.append(drafts.count - 1)
        return .visitChildren
    }

    // ponytail: "starts with an uppercase letter" stands in for "is a type name".
    // It also catches enum-like constants and misses lowercase types; upgrade to a symbol index if it matters.
    private func addReference(_ name: String) {
        guard let index = openTypes.last, name.first?.isUppercase == true else { return }
        let ownName = drafts[index].name.split(separator: ".").last.map(String.init)
        if name != ownName { drafts[index].references.insert(name) }
    }
}
