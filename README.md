# JavaScriptCore

Swift library for the JavaScriptCore engine from WebKit.

The package has two parts:

| Product | What it is |
| --- | --- |
| `JavaScriptCoreSwift` | A Swift API over the engine: contexts, values and functions made from closures |
| `CJavaScriptCore` | The engine's C API as a module, for code that wants it directly |

On Linux the engine is WebKit's `JSCOnly` port, which is JavaScriptCore built
alone with ICU as its one dependency. On Apple's platforms it is the system's
JavaScriptCore framework.

## Usage

```swift
import JavaScriptCoreSwift

let context = JSContext()

// Run a script.
let result = try context.evaluateScript("6 * 7")
print(result.toInt32()) // 42

// Give JavaScript a function.
context["greet"] = JSValue(function: { this, arguments in
    JSValue(string: "Hello, \(arguments[0])!", in: this.context)
}, in: context)
print(try context.evaluateScript("greet('world')")) // Hello, world!

// An uncaught exception is a Swift error.
do {
    try context.evaluateScript("missing()", sourceURL: "main.js")
} catch let error as JSError {
    print(error.name ?? "", error.message, error.line ?? 0)
}
```

Values keep their context alive, and a context keeps the functions given to it
alive. A closure that captures a `JSValue` therefore keeps its own context
alive for good: capture the context weakly and read values from it instead.

## Building the engine

`Scripts/build-engine.sh` downloads a WPE WebKit release, checks it against its
checksum, builds the `JSCOnly` port and installs the shared library, the C
API's headers and a pkg-config file named `javascriptcore`.

```bash
Scripts/build-engine.sh "$HOME/.local"
```

```bash
PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig" LD_LIBRARY_PATH="$HOME/.local/lib" swift test
```

It needs CMake, Ninja, a C++23 compiler, Ruby, Perl, Python 3 and ICU's
headers. Arguments after `--` go to CMake, which is where a cross build names
its toolchain file. The comment at the top of the script lists the environment
variables that choose the release and the build directory.

A distribution's WebKitGTK carries the same C API. To build against it
instead, give pkg-config a `javascriptcore.pc` that requires it:

```
Name: javascriptcore
Description: JavaScriptCore from WebKitGTK
Version: 2.54.0
Requires: javascriptcoregtk-4.1
```
