#if !os(macOS)
// Grip is a macOS app. This stub only exists so `swift build` / `swift test`
// for the platform-independent core also work on Linux CI.
@main
struct GripLinuxStub {
    static func main() {
        print("Grip draait alleen op macOS.")
    }
}
#endif
