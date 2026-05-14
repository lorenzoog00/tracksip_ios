import SwiftUI

struct WatchAddDrinkView: View {

    @ObservedObject var state: WatchState
    @Binding var isPresented: Bool
    @State private var lastAdded: String? = nil

    var body: some View {
        NavigationStack {
            List(state.drinkTypes) { drink in
                Button {
                    state.addDrink(drinkTypeId: drink.id)
                    lastAdded = drink.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: drink.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(Color(red: 0.83, green: 0.68, blue: 0.33))
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(drink.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(String(format: "%.1f%%", drink.abv))
                                .font(.system(size: 11))
                                .foregroundStyle(.gray)
                        }

                        if lastAdded == drink.id {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.22, green: 0.85, blue: 0.50))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
            .listStyle(.plain)
            .navigationTitle("Add Drink")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
