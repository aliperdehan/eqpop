import Cocoa

let cliArgs = Array(CommandLine.arguments.dropFirst())
if cliArgs.first == "--version" { print("eqpop \(eqpopVersion)"); exit(0) }
if cliArgs.first == "--selftest" { exit(selfTest()) }
if cliArgs.first == "--render" { exit(cliRender(Array(cliArgs.dropFirst()))) }

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
