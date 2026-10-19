import Cocoa

let cliArgs = Array(CommandLine.arguments.dropFirst())
if cliArgs.first == "--version" { print("eqpop \(eqpopVersion)"); exit(0) }
if cliArgs.first == "--selftest" { exit(selfTest()) }
if cliArgs.first == "--render" { exit(cliRender(Array(cliArgs.dropFirst()))) }

if let i = cliArgs.firstIndex(of: "--screenshot") {
    // a picture of the window for the README: scratch settings, sample text, no hotkey, no menu-bar item
    let sample = cliArgs.firstIndex(of: "--source").map { cliArgs[$0 + 1] }
        ?? "\\ce{CH4 + 2O2 -> CO2 + 2H2O}\n\\qquad \\Delta H^\\circ = \\SI{-890}{\\kilo\\joule\\per\\mole}"
    defaults.set(sample, forKey: "source")
    defaults.set(true, forKey: "preambleShown")
    App.screenshotPath = cliArgs[i + 1]
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
