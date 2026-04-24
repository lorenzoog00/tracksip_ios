import SwiftUI

struct DrinkType: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var defaultVolumeMl: Double
    var defaultAbv: Double
    var caloriesPerServing: Double
    var isPreset: Bool
    var icon: String

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
        default:                            return "cup.and.saucer.fill"
        }
    }

    var color: Color {
        switch icon {
        case "beer-outline", "beer":  return Color(hex: "#F0A830")
        case "wine":                  return Color(hex: "#C0392B")
        case "wine-sharp":            return Color(hex: "#ECF0F1")
        case "champagne", "sparkles": return Color(hex: "#F1C40F")
        default:                      return AppColors.accent
        }
    }
}

extension DrinkType {
    static let presets: [DrinkType] = [
        DrinkType(id: "beer",        name: "Beer",        defaultVolumeMl: 355,  defaultAbv: 5.0,  caloriesPerServing: 153,  isPreset: true, icon: "beer-outline"),
        DrinkType(id: "light-beer",  name: "Light Beer",  defaultVolumeMl: 355,  defaultAbv: 4.2,  caloriesPerServing: 103,  isPreset: true, icon: "beer-outline"),
        DrinkType(id: "ipa",         name: "IPA",         defaultVolumeMl: 355,  defaultAbv: 6.5,  caloriesPerServing: 195,  isPreset: true, icon: "beer-outline"),
        DrinkType(id: "red-wine",    name: "Red Wine",    defaultVolumeMl: 150,  defaultAbv: 13.5, caloriesPerServing: 125,  isPreset: true, icon: "wine"),
        DrinkType(id: "white-wine",  name: "White Wine",  defaultVolumeMl: 150,  defaultAbv: 12.0, caloriesPerServing: 121,  isPreset: true, icon: "wine-sharp"),
        DrinkType(id: "champagne",   name: "Champagne",   defaultVolumeMl: 150,  defaultAbv: 12.0, caloriesPerServing: 96,   isPreset: true, icon: "sparkles"),
        DrinkType(id: "tequila",     name: "Tequila",     defaultVolumeMl: 44,   defaultAbv: 40.0, caloriesPerServing: 97,   isPreset: true, icon: "flask-outline"),
        DrinkType(id: "vodka",       name: "Vodka",       defaultVolumeMl: 44,   defaultAbv: 40.0, caloriesPerServing: 97,   isPreset: true, icon: "flask-outline"),
        DrinkType(id: "whiskey",     name: "Whiskey",     defaultVolumeMl: 44,   defaultAbv: 40.0, caloriesPerServing: 105,  isPreset: true, icon: "flask"),
        DrinkType(id: "mezcal",      name: "Mezcal",      defaultVolumeMl: 44,   defaultAbv: 40.0, caloriesPerServing: 97,   isPreset: true, icon: "flask"),
        DrinkType(id: "margarita",   name: "Margarita",   defaultVolumeMl: 240,  defaultAbv: 13.0, caloriesPerServing: 274,  isPreset: true, icon: "restaurant"),
        DrinkType(id: "mojito",      name: "Mojito",      defaultVolumeMl: 240,  defaultAbv: 10.0, caloriesPerServing: 217,  isPreset: true, icon: "leaf"),
        DrinkType(id: "gin-tonic",   name: "Gin & Tonic", defaultVolumeMl: 240,  defaultAbv: 9.0,  caloriesPerServing: 175,  isPreset: true, icon: "water"),
        DrinkType(id: "pina-colada", name: "Piña Colada", defaultVolumeMl: 240,  defaultAbv: 10.0, caloriesPerServing: 245,  isPreset: true, icon: "sunny"),
        DrinkType(id: "hard-seltzer",name: "Hard Seltzer", defaultVolumeMl: 355, defaultAbv: 5.0,  caloriesPerServing: 100,  isPreset: true, icon: "snow"),
        DrinkType(id: "michelada",   name: "Michelada",   defaultVolumeMl: 355,  defaultAbv: 3.5,  caloriesPerServing: 160,  isPreset: true, icon: "beer-outline"),
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
