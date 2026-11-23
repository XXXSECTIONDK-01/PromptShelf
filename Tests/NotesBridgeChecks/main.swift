import Foundation
import JavaScriptCore

// Runs the exact shipping JXA in JavaScriptCore against in-memory Notes objects.
// Never evaluates Application/ObjC using Automation; no Notes app, user data or permissions are accessed.
let scriptURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/NotesBridge.js")
let fixtureURL = URL(fileURLWithPath: "Tests/NotesBridgeChecks/fixtures.js")
let context = JSContext()!
var failure: String?
context.exceptionHandler = { _, exception in failure = exception?.toString() ?? "Unknown JavaScript error" }
context.evaluateScript(try String(contentsOf: fixtureURL, encoding: .utf8))
context.evaluateScript(try String(contentsOf: scriptURL, encoding: .utf8))
let result = context.evaluateScript("runBridgeChecks()")
if let failure { fputs("FAIL: \(failure)\n", stderr); exit(1) }
print(result?.toString() ?? "No bridge results")
