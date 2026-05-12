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
