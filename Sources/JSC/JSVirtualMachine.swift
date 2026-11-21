import CJavaScriptCore

/// A heap that contexts share. Values can pass between the contexts of one
/// virtual machine, and the engine runs one thread at a time in each.
public final class JSVirtualMachine: @unchecked Sendable {
    let reference: JSContextGroupRef

    public init() {
        reference = JSContextGroupCreate()
    }

    deinit {
        JSContextGroupRelease(reference)
    }
}
