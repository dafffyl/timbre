import Testing

@testable import TimbreCore

@Test func azertyHasThreeRows() {
    #expect(KeyboardLayout.azerty.rows.count == 3)
}

@Test func azertyFirstRowStartsWithA() {
    #expect(KeyboardLayout.azerty.rows.first?.first == "A")
}
