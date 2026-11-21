import CJavaScriptCore

/// What a function made in Swift runs: it is given the call's `this` and
/// arguments, and what it throws is thrown in JavaScript.
public typealias JSFunctionBody = @Sendable (_ this: JSValue, _ arguments: [JSValue]) throws -> JSValue

extension JSValue {
    /// A function that runs a closure.
    ///
    /// The engine can call the function on any thread that uses the context,
    /// and keeps the closure until the function is collected. A `JSError`
    /// the closure throws is thrown as its value, and any other error as an
    /// `Error` with the error's description as its message.
    public convenience init(function body: @escaping JSFunctionBody, in context: JSContext) {
        let box = Unmanaged.passRetained(FunctionBox(body: body, context: context))
        let function: JSObjectRef = JSObjectMake(context.reference, FunctionBox.classReference, box.toOpaque())
        self.init(context: context, reference: function)
        // An object of a class is callable, but only `Function.prototype`
        // gives it `call`, `apply` and `bind`.
        let prototype = context["Function"]["prototype"]
        if prototype.isObject {
            JSObjectSetPrototype(context.reference, function, prototype.reference)
        }
    }
}

/// The closure behind a function, as the function object's private data.
private final class FunctionBox {
    let body: JSFunctionBody
    /// Weak, because the context owns the function that owns this.
    weak var context: JSContext?

    init(body: @escaping JSFunctionBody, context: JSContext) {
        self.body = body
        self.context = context
    }

    nonisolated(unsafe) static let classReference: JSClassRef = {
        let name: StaticString = "SwiftFunction"
        var definition = kJSClassDefinitionEmpty
        definition.className = UnsafeRawPointer(name.utf8Start).assumingMemoryBound(to: CChar.self)
        definition.callAsFunction = { reference, function, this, count, arguments, exception in
            guard let function, let data = JSObjectGetPrivate(function),
                  let context = Unmanaged<FunctionBox>.fromOpaque(data).takeUnretainedValue().context
            else { return JSValueMakeUndefined(reference) }
            let box = Unmanaged<FunctionBox>.fromOpaque(data).takeUnretainedValue()
            let this = this.map { JSValue(context: context, reference: $0) } ?? context.globalObject
            let arguments = (0 ..< count).compactMap { index in
                arguments?[index].map { JSValue(context: context, reference: $0) }
            }
            do {
                return try box.body(this, arguments).reference
            } catch let error as JSError {
                exception?.pointee = error.value.reference
            } catch {
                exception?.pointee = JSValue(newErrorFromMessage: String(describing: error), in: context).reference
            }
            return JSValueMakeUndefined(reference)
        }
        definition.finalize = { function in
            guard let function, let data = JSObjectGetPrivate(function) else { return }
            Unmanaged<FunctionBox>.fromOpaque(data).release()
        }
        return JSClassCreate(&definition)
    }()
}
