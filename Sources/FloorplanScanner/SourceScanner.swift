import SwiftParser
import SwiftSyntax

/// Parses one Swift source string and lists its imports and type declarations.
public func scanSource(_ source: String, path: String) -> FileSummary {
    let tree = Parser.parse(source: source)
    let collector = Collector(converter: SourceLocationConverter(fileName: path, tree: tree))
    collector.walk(tree)
    return FileSummary(path: path, imports: collector.imports.sorted(), types: collector.makeTypes(), dependencyKeys: collector.dependencyKeys, functions: collector.functions)
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
        var dependencies: Set<String> = []
        var calls: Set<String> = []
    }

    private let converter: SourceLocationConverter
    private var drafts: [Draft] = []
    /// Indices into `drafts` of the types we are currently inside; the last one is the innermost.
    private var openTypes: [Int] = []
    private var topLevelIndex: Int?
    private(set) var imports: Set<String> = []
    private(set) var dependencyKeys: [DependencyKey] = []
    private(set) var functions: [String] = []
    private var functionDepth = 0

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    func makeTypes() -> [TypeInfo] {
        drafts.map {
            TypeInfo(
                name: $0.name, kind: $0.kind, line: $0.line, inherits: $0.inherits,
                references: $0.references.sorted(), isReducer: $0.isReducer, composes: $0.composes,
                createsStores: $0.createsStores.sorted(), dependencies: $0.dependencies.sorted(), calls: $0.calls.sorted()
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

    // Only functions declared outside every type and outside other functions count as free functions.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if openTypes.isEmpty && functionDepth == 0 { functions.append(node.name.text) }
        functionDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: FunctionDeclSyntax) { functionDepth -= 1 }

    // `Store(initialState: ...) { Feature() }` marks the innermost type as the owner of that store.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        if let index = openTypes.last, callee == "Store", let reducer = trailingClosureReducerName(node) {
            drafts[index].createsStores.insert(reducer)
        }
        if let callee, callee.first?.isLowercase == true { drafts[openTypes.last ?? topLevelDraft()].calls.insert(callee) }
        return .visitChildren
    }

    // `@Dependency(\.eventClient) var ...` marks the innermost type as a user of "eventClient".
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let index = openTypes.last else { return .visitChildren }
        for case .attribute(let attribute) in node.attributes where attribute.attributeName.trimmedDescription == "Dependency" {
            if case .argumentList(let arguments) = attribute.arguments,
               let path = arguments.first?.expression.as(KeyPathExprSyntax.self),
               let key = path.components.first?.component.as(KeyPathPropertyComponentSyntax.self) {
                drafts[index].dependencies.insert(key.declName.baseName.text)
            }
        }
        return .visitChildren
    }

    // `extension DependencyValues { var eventClient: EventClient { get set } }` declares a key and its type.
    // Any other extension is listed as "Foo (extension)", so what its body uses is not lost.
    private var isDependencyValues: (ExtensionDeclSyntax) -> Bool { { $0.extendedType.trimmedDescription == "DependencyValues" } }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isDependencyValues(node) else {
            return open(node, .extension, node.extendedType.trimmedDescription + " (extension)", node.inheritanceClause, node.attributes, node.memberBlock)
        }
        for variable in node.memberBlock.members.compactMap({ $0.decl.as(VariableDeclSyntax.self) }) {
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let type = binding.typeAnnotation?.type.trimmedDescription else { continue }
                dependencyKeys.append(DependencyKey(name: name, type: type))
            }
        }
        return .skipChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { if !isDependencyValues(node) { openTypes.removeLast() } }

    private func open(
        _ node: some SyntaxProtocol, _ kind: TypeKind, _ simpleName: String, _ clause: InheritanceClauseSyntax?,
        _ attributes: AttributeListSyntax, _ members: MemberBlockSyntax
    ) -> SyntaxVisitorContinueKind {
        let parent = openTypes.last.flatMap { drafts[$0].kind == .extension ? nil : drafts[$0].name + "." } ?? ""
        let name = parent + simpleName
        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        let inherits = clause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let isReducer = kind != .extension && isReducerDeclaration(attributes: attributes, inherits: inherits)
        let composes = isReducer ? reducerLinks(in: members, typeName: name, isEnum: kind == .enum) : []
        drafts.append(Draft(name: name, kind: kind, line: line, inherits: inherits, isReducer: isReducer, composes: composes))
        openTypes.append(drafts.count - 1)
        return .visitChildren
    }

    // ponytail: "starts with an uppercase letter" stands in for "is a type name".
    // It also catches enum-like constants and misses lowercase types; upgrade to a symbol index if it matters.
    private func addReference(_ name: String) {
        guard name.first?.isUppercase == true else { return }
        let index = openTypes.last ?? topLevelDraft()
        let ownName = drafts[index].name.split(separator: ".").last.map(String.init)
        if name != ownName { drafts[index].references.insert(name) }
    }

    /// The entry that collects references made outside every type. Created on first use.
    private func topLevelDraft() -> Int {
        if let topLevelIndex { return topLevelIndex }
        drafts.append(Draft(name: "(top level code)", kind: .topLevel, line: 1, inherits: [], isReducer: false, composes: []))
        topLevelIndex = drafts.count - 1
        return drafts.count - 1
    }
}
