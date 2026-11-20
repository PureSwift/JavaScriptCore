import CJavaScriptCore

/// A JavaScript value, kept alive for as long as this object is.
///
/// A value holds its context. A function made from a closure that captures a
/// value is held by that same context, so the two keep each other alive:
/// capture the context weakly and look values up from it instead.
public final class JSValue: @unchecked Sendable {
    public let context: JSContext
    let reference: JSValueRef

    init(context: JSContext, reference: JSValueRef) {
        self.context = context
        self.reference = reference
        JSValueProtect(context.reference, reference)
    }

    deinit {
        JSValueUnprotect(context.reference, reference)
    }

    // MARK: Making values

    public convenience init(undefinedIn context: JSContext) {
        self.init(context: context, reference: JSValueMakeUndefined(context.reference))
    }

    public convenience init(nullIn context: JSContext) {
        self.init(context: context, reference: JSValueMakeNull(context.reference))
    }

    public convenience init(bool value: Bool, in context: JSContext) {
        self.init(context: context, reference: JSValueMakeBoolean(context.reference, value))
    }

    public convenience init(double value: Double, in context: JSContext) {
        self.init(context: context, reference: JSValueMakeNumber(context.reference, value))
    }

    public convenience init(int32 value: Int32, in context: JSContext) {
        self.init(double: Double(value), in: context)
    }

    public convenience init(string value: String, in context: JSContext) {
        self.init(context: context, reference: value.withJSString { JSValueMakeString(context.reference, $0) })
    }

    /// An empty object.
    public convenience init(newObjectIn context: JSContext) {
        self.init(context: context, reference: JSObjectMake(context.reference, nil, nil))
    }

    /// An array of the given values.
    public convenience init(array values: [JSValue] = [], in context: JSContext) {
        let references: [JSValueRef?] = values.map(\.reference)
        // Making an array from values cannot throw.
        self.init(context: context, reference: JSObjectMakeArray(context.reference, references.count, references, nil))
    }

    /// An `Error` object with the given message.
    public convenience init(newErrorFromMessage message: String, in context: JSContext) {
        let message = JSValue(string: message, in: context)
        let arguments: [JSValueRef?] = [message.reference]
        self.init(context: context, reference: JSObjectMakeError(context.reference, 1, arguments, nil))
    }

    /// The value JSON text describes, or nil where the text is not JSON.
    public convenience init?(json: String, in context: JSContext) {
        let reference: JSValueRef? = json.withJSString { JSValueMakeFromJSONString(context.reference, $0) }
        guard let reference else { return nil }
        self.init(context: context, reference: reference)
    }

    // MARK: Types

    public var isUndefined: Bool { JSValueIsUndefined(context.reference, reference) }
    public var isNull: Bool { JSValueIsNull(context.reference, reference) }
    public var isBoolean: Bool { JSValueIsBoolean(context.reference, reference) }
    public var isNumber: Bool { JSValueIsNumber(context.reference, reference) }
    public var isString: Bool { JSValueIsString(context.reference, reference) }
    public var isSymbol: Bool { JSValueIsSymbol(context.reference, reference) }
    public var isObject: Bool { JSValueIsObject(context.reference, reference) }
    public var isArray: Bool { JSValueIsArray(context.reference, reference) }
    public var isDate: Bool { JSValueIsDate(context.reference, reference) }

    public var isFunction: Bool {
        guard let object else { return false }
        return JSObjectIsFunction(context.reference, object)
    }

    /// The value as an object reference, where it is an object.
    var object: JSObjectRef? {
        isObject ? reference : nil
    }

    /// The value as an object, as JavaScript's own conversion makes one.
    func toObject() throws -> JSObjectRef {
        let object: JSObjectRef? = try context.check { JSValueToObject(context.reference, reference, $0) }
        guard let object else { throw JSError(JSValue(newErrorFromMessage: "Not an object", in: context)) }
        return object
    }

    // MARK: Converting

    public func toBool() -> Bool {
        JSValueToBoolean(context.reference, reference)
    }

    /// The value as a number, which is NaN where the conversion throws.
    public func toDouble() -> Double {
        var exception: JSValueRef?
        let number = JSValueToNumber(context.reference, reference, &exception)
        return exception == nil ? number : .nan
    }

    /// The value as JavaScript's `ToInt32` gives it: truncated, and wrapped
    /// around 32 bits.
    public func toInt32() -> Int32 {
        let number = toDouble()
        guard number.isFinite else { return 0 }
        let wrapped = number.rounded(.towardZero).truncatingRemainder(dividingBy: 4_294_967_296)
        return Int32(truncatingIfNeeded: Int64(wrapped))
    }

    /// The value as text, which is empty where the conversion throws.
    public func toString() -> String {
        String(consuming: JSValueToStringCopy(context.reference, reference, nil)) ?? ""
    }

    /// The elements of an array, or nil for any other value.
    public func toArray() -> [JSValue]? {
        guard isArray else { return nil }
        return (0 ..< Int(self["length"].toInt32())).map { self[$0] }
    }

    /// The value as JSON text, or nil where JSON has no form for it, such as
    /// `undefined` or a function.
    ///
    /// - Parameter indent: The number of spaces to indent nested values by.
    public func toJSON(indent: Int = 0) throws -> String? {
        let string: JSStringRef? = try context.check {
            JSValueCreateJSONString(context.reference, reference, UInt32(indent), $0)
        }
        return String(consuming: string)
    }

    // MARK: Comparing

    /// Whether the values are equal as `===` has it.
    public func isEqual(to other: JSValue) -> Bool {
        JSValueIsStrictEqual(context.reference, reference, other.reference)
    }

    /// Whether the values are equal as `==` has it.
    public func isEqualWithTypeCoercion(to other: JSValue) -> Bool {
        JSValueIsEqual(context.reference, reference, other.reference, nil)
    }

    /// Whether the value is an instance as `instanceof` has it.
    public func isInstance(of constructor: JSValue) -> Bool {
        guard let constructor = constructor.object else { return false }
        return JSValueIsInstanceOfConstructor(context.reference, reference, constructor, nil)
    }

    // MARK: Properties

    /// The value of a property, which is `undefined` for one the value does
    /// not have.
    ///
    /// - Throws: `JSError` where the value has no properties, or a getter
    ///   throws.
    public func value(forProperty name: String) throws -> JSValue {
        let object = try toObject()
        let result: JSValueRef? = try name.withJSString { name in
            try context.check { JSObjectGetProperty(context.reference, object, name, $0) }
        }
        guard let result else { return JSValue(undefinedIn: context) }
        return JSValue(context: context, reference: result)
    }

    /// - Throws: `JSError` where the value has no properties, or a setter
    ///   throws.
    public func setValue(_ value: JSValue, forProperty name: String) throws {
        let object = try toObject()
        try name.withJSString { name in
            try context.check {
                JSObjectSetProperty(context.reference, object, name, value.reference, JSPropertyAttributes(kJSPropertyAttributeNone), $0)
            }
        }
    }

    public func value(at index: Int) throws -> JSValue {
        let object = try toObject()
        let result: JSValueRef? = try context.check {
            JSObjectGetPropertyAtIndex(context.reference, object, UInt32(index), $0)
        }
        guard let result else { return JSValue(undefinedIn: context) }
        return JSValue(context: context, reference: result)
    }

    public func setValue(_ value: JSValue, at index: Int) throws {
        let object = try toObject()
        try context.check {
            JSObjectSetPropertyAtIndex(context.reference, object, UInt32(index), value.reference, $0)
        }
    }

    public func hasProperty(_ name: String) -> Bool {
        guard let object else { return false }
        return name.withJSString { JSObjectHasProperty(context.reference, object, $0) }
    }

    /// Whether the property is gone, which it is not where it cannot be
    /// deleted.
    @discardableResult
    public func deleteProperty(_ name: String) -> Bool {
        guard let object else { return false }
        return name.withJSString { JSObjectDeleteProperty(context.reference, object, $0, nil) }
    }

    /// The names of the value's enumerable properties.
    public var propertyNames: [String] {
        guard let object, let names: JSPropertyNameArrayRef = JSObjectCopyPropertyNames(context.reference, object) else {
            return []
        }
        defer { JSPropertyNameArrayRelease(names) }
        return (0 ..< JSPropertyNameArrayGetCount(names)).map {
            String(JSPropertyNameArrayGetNameAtIndex(names, $0))
        }
    }

    /// A property by name. Reading gives `undefined` and writing does
    /// nothing where the throwing forms would throw.
    public subscript(name: String) -> JSValue {
        get { (try? value(forProperty: name)) ?? JSValue(undefinedIn: context) }
        set { try? setValue(newValue, forProperty: name) }
    }

    /// A property by index, as for an array's elements.
    public subscript(index: Int) -> JSValue {
        get { (try? value(at: index)) ?? JSValue(undefinedIn: context) }
        set { try? setValue(newValue, at: index) }
    }

    // MARK: Calling

    /// Calls the value as a function.
    ///
    /// - Parameter this: The call's `this`, which is the global object when
    ///   nil.
    /// - Throws: `JSError` where the value is not a function, or it throws.
    @discardableResult
    public func call(withArguments arguments: [JSValue] = [], this: JSValue? = nil) throws -> JSValue {
        guard let object, JSObjectIsFunction(context.reference, object) else {
            throw JSError(JSValue(newErrorFromMessage: "Not a function", in: context))
        }
        let references: [JSValueRef?] = arguments.map(\.reference)
        let result: JSValueRef? = try context.check {
            JSObjectCallAsFunction(context.reference, object, this?.object, references.count, references, $0)
        }
        guard let result else { return JSValue(undefinedIn: context) }
        return JSValue(context: context, reference: result)
    }

    /// Calls the value as a constructor, as `new` does.
    public func construct(withArguments arguments: [JSValue] = []) throws -> JSValue {
        guard let object, JSObjectIsConstructor(context.reference, object) else {
            throw JSError(JSValue(newErrorFromMessage: "Not a constructor", in: context))
        }
        let references: [JSValueRef?] = arguments.map(\.reference)
        let result: JSObjectRef? = try context.check {
            JSObjectCallAsConstructor(context.reference, object, references.count, references, $0)
        }
        guard let result else { return JSValue(undefinedIn: context) }
        return JSValue(context: context, reference: result)
    }

    /// Calls a method of the value, with the value as `this`.
    @discardableResult
    public func invokeMethod(_ name: String, withArguments arguments: [JSValue] = []) throws -> JSValue {
        try value(forProperty: name).call(withArguments: arguments, this: self)
    }
}

extension JSValue: CustomStringConvertible {
    public var description: String { toString() }
}
