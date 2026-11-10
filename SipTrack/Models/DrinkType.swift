import SwiftUI

struct DrinkType: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var defaultVolumeMl: Double
    var defaultAbv: Double
    var caloriesPerServing: Double
    var isPreset: Bool
    var icon: String
    var colorHex: String?
    var defaultDrinkingDurationMinutes: Int? = nil

    // Typical time to finish one serving. Falls back to a per-icon heuristic so existing
    // user data without this field still gets a physically reasonable absorption curve.
    var effectiveDrinkingMinutes: Int {
        if let v = defaultDrinkingDurationMinutes, v > 0 { return v }
        switch icon {
        case "beer-outline", "beer":                          return 20
        case "wine", "wine-sharp", "champagne", "sparkles":   return 30
        case "flask", "flask-outline":                        return 1   // shots — gulped
        case "restaurant", "leaf", "water", "sunny", "snow":  return 25  // cocktails
        case "cup":                                          return 25
        default:                                              return 15
        }
    }

    var sfSymbol: String {
        switch icon {
        case "beer-outline", "beer":        return "mug.fill"
        case "wine", "wine-outline":        return "wineglass.fill"
        case "wine-sharp":                  return "wineglass"
        case "champagne", "sparkles":       return "sparkles"
        case "flask", "flask-outline":      return "flask.fill"
        case "restaurant":                  return "fork.knife"
        case "leaf":                        return "leaf.fill"
        case "water":                       return "drop.fill"
        case "snow":                        return "snowflake"
        case "sunny":                       return "sun.max.fill"
        case "cup":                         return "cup.and.saucer.fill"
        default:                            return "cup.and.saucer.fill"
        }
    }

    #if !os(watchOS)
    var color: Color {
        if let hex = colorHex { return Color(hex: hex) }
        switch icon {
        case "beer-outline", "beer":  return Color(hex: "#F0A830")
        case "wine":                  return Color(hex: "#C0392B")
        case "wine-sharp":            return Color(hex: "#ECF0F1")
        case "champagne", "sparkles": return Color(hex: "#F1C40F")
        default:                      return AppColors.accent
        }
    }
    #endif
}

extension DrinkType {
    static let presets: [DrinkType] = [
        DrinkType(id: "beer",        name: "Beer",        defaultVolumeMl: 355,  defaultAbv: 5.0,  caloriesPerServing: 153,  isPreset: true, icon: "beer-outline",   defaultDrinkingDurationMinutes: 20),
        DrinkType(id: "light-beer",  name: "Light Beer",  defaultVolumeMl: 355,  defaultAbv: 4.2,  caloriesPerServing: 103,  isPreset: true, icon: "beer-outline",   defaultDrinkingDurationMinutes: 20),
        DrinkType(id: "ipa",         name: "IPA",         defaultVolumeMl: 355,  defaultAbv: 6.5,  caloriesPerServing: 195,  isPreset: true, icon: "beer-outline",   defaultDrinkingDurationMinutes: 25),
        DrinkType(id: "red-wine",    name: "Red Wine",    defaultVolumeMl: 150,  defaultAbv: 13.5, caloriesPerServing: 125,  isPreset: true, icon: "wine",           defaultDrinkingDurationMinutes: 30),
        DrinkType(id: "white-wine",  name: "White Wine",  defaultVolumeMl: 150,  defaultAbv: 12.0, caloriesPerServing: 121,  isPreset: true, icon: "wine-sharp",     defaultDrinkingDurationMinutes: 30),
        DrinkType(id: "champagne",   name: "Champagne",   defaultVolumeMl: 150,  defaultAbv: 12.0, caloriesPerServing: 96,   isPreset: true, icon: "sparkles",       defaultDrinkingDurationMinutes: 30),
        DrinkType(id: "tequila",     name: "Tequila",     defaultVolumeMl: 44,   defaultAbv: 40.0, caloriesPerServing: 97,   isPreset: true, icon: "flask-outline",  defaultDrinkingDurationMinutes: 1),
        DrinkType(id: "vodka",       name: "Vodka",       defaultVolumeMl: 44,   defaultAbv: 40.0, caloriesPerServing: 97,   isPreset: true, icon: "flask-outline",  defaultDrinkingDurationMinutes: 1),
        DrinkType(id: "whiskey",     name: "Whiskey",     defaultVolumeMl: 44,   defaultAbv: 40.0, caloriesPerServing: 105,  isPreset: true, icon: "flask",          defaultDrinkingDurationMinutes: 5),
        DrinkType(id: "mezcal",      name: "Mezcal",      defaultVolumeMl: 44,   defaultAbv: 40.0, caloriesPerServing: 97,   isPreset: true, icon: "flask",          defaultDrinkingDurationMinutes: 1),
        DrinkType(id: "margarita",   name: "Margarita",   defaultVolumeMl: 240,  defaultAbv: 13.0, caloriesPerServing: 274,  isPreset: true, icon: "restaurant",     defaultDrinkingDurationMinutes: 25),
        DrinkType(id: "mojito",      name: "Mojito",      defaultVolumeMl: 240,  defaultAbv: 10.0, caloriesPerServing: 217,  isPreset: true, icon: "leaf",           defaultDrinkingDurationMinutes: 25),
        DrinkType(id: "gin-tonic",   name: "Gin & Tonic", defaultVolumeMl: 240,  defaultAbv: 9.0,  caloriesPerServing: 175,  isPreset: true, icon: "water",          defaultDrinkingDurationMinutes: 25),
        DrinkType(id: "pina-colada", name: "Piña Colada", defaultVolumeMl: 240,  defaultAbv: 10.0, caloriesPerServing: 245,  isPreset: true, icon: "sunny",          defaultDrinkingDurationMinutes: 25),
        DrinkType(id: "hard-seltzer",name: "Hard Seltzer", defaultVolumeMl: 355, defaultAbv: 5.0,  caloriesPerServing: 100,  isPreset: true, icon: "snow",           defaultDrinkingDurationMinutes: 20),
        DrinkType(id: "michelada",   name: "Michelada",   defaultVolumeMl: 355,  defaultAbv: 3.5,  caloriesPerServing: 160,  isPreset: true, icon: "beer-outline",   defaultDrinkingDurationMinutes: 30),
        // Popular in Mexico and missing until now, so every user had to build
        // them by hand. ABV is derived from the pour the recipes agree on
        // rather than taken from a recipe site's own claim: a Paloma's 2 oz of
        // 40% tequila is 24 ml of ethanol, and stating the finished volume with
        // ice is what makes volume × ABV come back to that. Difford's Guide
        // puts a Paloma at 9.63% and 168 kcal, which is where these land.
        DrinkType(id: "paloma",      name: "Paloma",      defaultVolumeMl: 240,  defaultAbv: 9.0,  caloriesPerServing: 170,  isPreset: true, icon: "water",          defaultDrinkingDurationMinutes: 25),
        // 2 oz Licor 43 at 31% over 2 oz espresso. Sweet liqueur, so the
        // calories sit above what the alcohol alone accounts for.
        DrinkType(id: "carajillo",   name: "Carajillo",   defaultVolumeMl: 150,  defaultAbv: 12.0, caloriesPerServing: 150,  isPreset: true, icon: "cup",            defaultDrinkingDurationMinutes: 15),
        // Served in a big clay cup: same tequila as a Paloma, far more juice
        // and soda around it, so it is weaker per ml and takes longer.
        DrinkType(id: "cantarito",   name: "Cantarito",   defaultVolumeMl: 350,  defaultAbv: 6.5,  caloriesPerServing: 240,  isPreset: true, icon: "sunny",          defaultDrinkingDurationMinutes: 30),
        DrinkType(id: "charro-negro", name: "Charro Negro", defaultVolumeMl: 240, defaultAbv: 9.5, caloriesPerServing: 180,  isPreset: true, icon: "water",          defaultDrinkingDurationMinutes: 25),
        DrinkType(id: "cuba-libre",  name: "Cuba Libre",  defaultVolumeMl: 240,  defaultAbv: 9.5,  caloriesPerServing: 180,  isPreset: true, icon: "water",          defaultDrinkingDurationMinutes: 25),
        DrinkType(id: "vampiro",     name: "Vampiro",     defaultVolumeMl: 300,  defaultAbv: 8.0,  caloriesPerServing: 200,  isPreset: true, icon: "restaurant",     defaultDrinkingDurationMinutes: 30),
        // Fermented rather than distilled, so it sits near a beer: sources put
        // it at 4–6% and a commercial can declares 5%.
        DrinkType(id: "pulque",      name: "Pulque",      defaultVolumeMl: 300,  defaultAbv: 5.0,  caloriesPerServing: 140,  isPreset: true, icon: "leaf",           defaultDrinkingDurationMinutes: 30),
    ]

    static func mergedWith(custom: [DrinkType]) -> [DrinkType] {
        var result = presets
        for c in custom {
            if let idx = result.firstIndex(where: { $0.id == c.id }) {
                result[idx] = c
            } else {
                result.append(c)
            }
        }
        return result
    }
}

extension DrinkType {
    var drinkCategory: String {
        switch icon {
        case "beer-outline", "beer", "snow": return "beer"
        case "wine", "wine-sharp", "champagne", "sparkles": return "wine"
        case "flask", "flask-outline":
            return (id == "tequila" || id == "mezcal") ? "agave" : "spirits"
        default: return "cocktails"
        }
    }
}

// MARK: - Serving sizes (dose fidelity)

struct ServingSizeOption: Identifiable, Hashable {
    let label: String
    let volumeMl: Double
    var id: String { label }
}

extension DrinkType {
    // caloriesPerServing describes one pour at defaultVolumeMl, so a larger or smaller
    // serving has to scale with it — otherwise a pint counts the calories of a bottle.
    func calories(volumeMl: Double, quantity: Int) -> Double {
        guard defaultVolumeMl > 0 else { return caloriesPerServing * Double(quantity) }
        return caloriesPerServing * (volumeMl / defaultVolumeMl) * Double(quantity)
    }
}

extension DrinkType {
    var servingSizeOptions: [ServingSizeOption] {
        let categoryLarge: Double = switch drinkCategory {
        case "spirits", "agave": 88
        case "wine": 250
        case "beer": 568
        default: 360
        }
        // Custom drinks can already be larger than the category's usual large pour.
        let largeVolume = categoryLarge > defaultVolumeMl ? categoryLarge : (defaultVolumeMl * 1.5).rounded(.up)
        return [.init(label: "Standard", volumeMl: defaultVolumeMl),
                .init(label: "Large", volumeMl: largeVolume)]
    }
}
