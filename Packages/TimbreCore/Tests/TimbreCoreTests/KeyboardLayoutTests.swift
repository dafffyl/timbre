import Testing

@testable import TimbreCore

@Test func azertyHasThreeRows() {
    #expect(KeyboardLayout.azerty.rows.count == 3)
}

@Test func azertyFirstRowStartsWithA() {
    #expect(KeyboardLayout.azerty.rows.first?.first == "A")
}

@Test func numbersAndPunctuationFirstRowIsDigits() {
    #expect(KeyboardLayout.numbersAndPunctuation.rows.first == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
}

@Test func diacriticVariantsAreCaseInsensitiveOnLookup() {
    #expect(DiacriticVariants.variants(for: "e") == ["é", "è", "ê", "ë"])
    #expect(DiacriticVariants.variants(for: "E") == ["é", "è", "ê", "ë"])
}

@Test func diacriticVariantsIsEmptyForLetterWithoutAccent() {
    #expect(DiacriticVariants.variants(for: "k").isEmpty)
}
