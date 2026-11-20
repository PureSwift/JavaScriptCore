import Testing
import JSC

@Suite struct ContextTests {
    @Test func evaluatesAScript() throws {
        let context = JSContext()
        let result = try context.evaluateScript("6 * 7")
        #expect(result.isNumber)
        #expect(result.toInt32() == 42)
    }

    @Test func keepsGlobalsBetweenScripts() throws {
        let context = JSContext()
        try context.evaluateScript("var greeting = 'hello'")
        #expect(context["greeting"].toString() == "hello")
        context["count"] = JSValue(int32: 3, in: context)
        #expect(try context.evaluateScript("count + 1").toInt32() == 4)
    }

    @Test func throwsAnUncaughtException() throws {
        let context = JSContext()
        let error = try #require(throws: JSError.self) {
            try context.evaluateScript("\nmissing()", sourceURL: "test.js")
        }
        #expect(error.name == "ReferenceError")
        #expect(error.message.contains("missing"))
        #expect(error.line == 2)
        #expect(error.description.hasPrefix("ReferenceError"))
    }

    @Test func throwsASyntaxError() throws {
        let context = JSContext()
        #expect(throws: JSError.self) { try context.checkSyntax("let = ;") }
        try context.checkSyntax("let value = 1;")
    }

    @Test func throwsValuesThatAreNotErrors() throws {
        let context = JSContext()
        let error = try #require(throws: JSError.self) { try context.evaluateScript("throw 'plain'") }
        #expect(error.message == "plain")
        #expect(error.name == nil)
    }

    @Test func sharesValuesWithinAVirtualMachine() throws {
        let machine = JSVirtualMachine()
        let first = JSContext(virtualMachine: machine)
        let second = JSContext(virtualMachine: machine)
        second["shared"] = try first.evaluateScript("({ answer: 42 })")
        #expect(try second.evaluateScript("shared.answer").toInt32() == 42)
    }

    @Test func namesTheContext() {
        let context = JSContext()
        context.name = "Tests"
        #expect(context.name == "Tests")
    }
}

@Suite struct ValueTests {
    @Test func tellsTypesApart() throws {
        let context = JSContext()
        #expect(JSValue(undefinedIn: context).isUndefined)
        #expect(JSValue(nullIn: context).isNull)
        #expect(JSValue(bool: true, in: context).isBoolean)
        #expect(JSValue(double: 1.5, in: context).isNumber)
        #expect(JSValue(string: "text", in: context).isString)
        #expect(JSValue(newObjectIn: context).isObject)
        #expect(JSValue(array: [], in: context).isArray)
        #expect(try context.evaluateScript("Symbol('s')").isSymbol)
        #expect(try context.evaluateScript("new Date(0)").isDate)
        #expect(try context.evaluateScript("(function () {})").isFunction)
        #expect(!JSValue(newObjectIn: context).isFunction)
    }

    @Test func convertsStrings() throws {
        let context = JSContext()
        let text = "naïve 日本語 🙂 a\u{0}b"
        let value = JSValue(string: text, in: context)
        #expect(value.toString() == text)
        context["text"] = value
        #expect(try context.evaluateScript("text.length").toInt32() == Int32(text.utf16.count))
        #expect(try context.evaluateScript("'🙂'").toString() == "🙂")
    }

    @Test func convertsNumbers() throws {
        let context = JSContext()
        #expect(try context.evaluateScript("'12.5'").toDouble() == 12.5)
        #expect(try context.evaluateScript("-7.9").toInt32() == -7)
        #expect(try context.evaluateScript("4294967298").toInt32() == 2)
        #expect(try context.evaluateScript("2147483648").toInt32() == Int32.min)
        #expect(try context.evaluateScript("NaN").toInt32() == 0)
        #expect(try context.evaluateScript("({})").toDouble().isNaN)
        #expect(try context.evaluateScript("''").toBool() == false)
        #expect(try context.evaluateScript("'x'").toBool())
    }

    @Test func readsAndWritesProperties() throws {
        let context = JSContext()
        let object = JSValue(newObjectIn: context)
        object["name"] = JSValue(string: "Cacao", in: context)
        object["size"] = JSValue(int32: 2, in: context)
        #expect(object["name"].toString() == "Cacao")
        #expect(object["missing"].isUndefined)
        #expect(object.hasProperty("size"))
        #expect(object.propertyNames == ["name", "size"])
        #expect(object.deleteProperty("size"))
        #expect(!object.hasProperty("size"))
    }

    @Test func throwsFromAccessors() throws {
        let context = JSContext()
        let object = try context.evaluateScript("({ get broken() { throw new TypeError('no') } })")
        #expect(object["broken"].isUndefined)
        let error = try #require(throws: JSError.self) { try object.value(forProperty: "broken") }
        #expect(error.name == "TypeError")
        #expect(throws: JSError.self) { try JSValue(nullIn: context).value(forProperty: "any") }
    }

    @Test func convertsArrays() throws {
        let context = JSContext()
        let array = JSValue(array: [1, 2, 3].map { JSValue(int32: $0, in: context) }, in: context)
        array[3] = JSValue(int32: 4, in: context)
        #expect(array["length"].toInt32() == 4)
        #expect(array.toArray()?.map { $0.toInt32() } == [1, 2, 3, 4])
        #expect(JSValue(newObjectIn: context).toArray() == nil)
    }

    @Test func convertsJSON() throws {
        let context = JSContext()
        let value = try #require(JSValue(json: #"{"list":[1,true,null],"text":"é"}"#, in: context))
        #expect(value["list"][1].toBool())
        #expect(try value.toJSON() == #"{"list":[1,true,null],"text":"é"}"#)
        #expect(try value["list"].toJSON(indent: 2) == "[\n  1,\n  true,\n  null\n]")
        #expect(JSValue(json: "{nope", in: context) == nil)
        #expect(try JSValue(undefinedIn: context).toJSON() == nil)
    }

    @Test func comparesValues() throws {
        let context = JSContext()
        let one = JSValue(int32: 1, in: context)
        let text = JSValue(string: "1", in: context)
        #expect(one.isEqual(to: JSValue(double: 1, in: context)))
        #expect(!one.isEqual(to: text))
        #expect(one.isEqualWithTypeCoercion(to: text))
        #expect(try context.evaluateScript("[]").isInstance(of: context["Array"]))
        #expect(!one.isInstance(of: context["Array"]))
    }

    @Test func callsFunctions() throws {
        let context = JSContext()
        let add = try context.evaluateScript("(function (a, b) { return a + b })")
        let sum = try add.call(withArguments: [JSValue(int32: 2, in: context), JSValue(int32: 3, in: context)])
        #expect(sum.toInt32() == 5)
        let list = try context["Array"].construct(withArguments: [JSValue(int32: 3, in: context)])
        #expect(list["length"].toInt32() == 3)
        let joined = try context.evaluateScript("['a', 'b']").invokeMethod("join", withArguments: [JSValue(string: "-", in: context)])
        #expect(joined.toString() == "a-b")
        #expect(throws: JSError.self) { try JSValue(newObjectIn: context).call() }
        let error = try #require(throws: JSError.self) { try context.evaluateScript("(function () { throw new RangeError('far') })").call() }
        #expect(error.name == "RangeError")
    }

    @Test func survivesGarbageCollection() throws {
        let context = JSContext()
        let value = try context.evaluateScript("({ kept: 'yes' })")
        try context.evaluateScript("for (let i = 0; i < 100000; i++) { ({ i }) }")
        context.collectGarbage()
        #expect(value["kept"].toString() == "yes")
    }
}

@Suite struct FunctionTests {
    @Test func callsAClosure() throws {
        let context = JSContext()
        context["double"] = JSValue(function: { this, arguments in
            JSValue(double: arguments[0].toDouble() * 2, in: this.context)
        }, in: context)
        #expect(try context.evaluateScript("double(21)").toInt32() == 42)
        #expect(try context.evaluateScript("typeof double").toString() == "function")
        #expect(context["double"].isFunction)
    }

    @Test func passesThis() throws {
        let context = JSContext()
        let object = try context.evaluateScript("({ name: 'object' })")
        object["describe"] = JSValue(function: { this, _ in this["name"] }, in: context)
        #expect(try object.invokeMethod("describe").toString() == "object")
    }

    @Test func behavesAsAFunction() throws {
        let context = JSContext()
        context["count"] = JSValue(function: { this, arguments in
            JSValue(int32: Int32(arguments.count), in: this.context)
        }, in: context)
        #expect(try context.evaluateScript("count.call(null, 1, 2)").toInt32() == 2)
        #expect(try context.evaluateScript("count.apply(null, [1, 2, 3])").toInt32() == 3)
        #expect(try context.evaluateScript("count.bind(null, 1)(2, 3, 4)").toInt32() == 4)
        #expect(try context.evaluateScript("[1, 2].map(count)[0]").toInt32() == 3)
    }

    @Test func throwsIntoJavaScript() throws {
        struct Failure: Error, CustomStringConvertible {
            var description: String { "it failed" }
        }
        let context = JSContext()
        context["fail"] = JSValue(function: { _, _ in throw Failure() }, in: context)
        #expect(try context.evaluateScript("try { fail() } catch (error) { error.message }").toString() == "it failed")
        context["rethrow"] = JSValue(function: { this, arguments in
            throw JSError(arguments[0])
        }, in: context)
        #expect(try context.evaluateScript("try { rethrow(7) } catch (error) { error }").toInt32() == 7)
        let error = try #require(throws: JSError.self) { try context.evaluateScript("fail()") }
        #expect(error.message == "it failed")
    }

    @Test func releasesTheClosure() throws {
        final class Token: Sendable {}
        weak var token: Token?
        do {
            let context = JSContext()
            let strong = Token()
            token = strong
            context["hold"] = JSValue(function: { this, _ in
                _ = strong
                return JSValue(undefinedIn: this.context)
            }, in: context)
            try context.evaluateScript("hold()")
        }
        #expect(token == nil)
    }
}
