import SwiftUI

struct UnitConverterTool: Tool {
    let id = "units"
    let name = "Unit Converter"
    let icon = "arrow.triangle.2.circlepath"
    let category: ToolCategory = .converter
    let description = "Length, weight, temp, data"

    var content: AnyView { AnyView(UnitConverterView()) }
}

struct UnitConverterView: View {
    enum Category: String, CaseIterable {
        case length = "Length"
        case weight = "Weight"
        case temperature = "Temperature"
        case data = "Data"
    }

    @State private var category: Category = .length
    @State private var fromUnit = 0
    @State private var toUnit = 1
    @State private var input = "1"
    @State private var result = ""

    private var units: [String] {
        switch category {
        case .length: return ["m", "km", "cm", "mm", "mi", "yd", "ft", "in"]
        case .weight: return ["kg", "g", "mg", "lb", "oz", "t"]
        case .temperature: return ["°C", "°F", "K"]
        case .data: return ["B", "KB", "MB", "GB", "TB", "KiB", "MiB", "GiB"]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Category", selection: $category) {
                    ForEach(Category.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: category) { _ in
                    fromUnit = 0; toUnit = 1; convert()
                }

                PurpleTextField(placeholder: "Value", text: $input)
                    .onChange(of: input) { _ in convert() }

                HStack {
                    Picker("From", selection: $fromUnit) {
                        ForEach(0..<units.count, id: \.self) { Text(units[$0]).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                    .onChange(of: fromUnit) { _ in convert() }

                    Image(systemName: "arrow.right")
                        .foregroundColor(Theme.primaryLight)

                    Picker("To", selection: $toUnit) {
                        ForEach(0..<units.count, id: \.self) { Text(units[$0]).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                    .onChange(of: toUnit) { _ in convert() }
                }

                ResultBox(title: "Result", value: result) {}

                PurpleButton(title: "Copy", icon: "doc.on.doc") {
                    UIPasteboard.general.string = result
                    Haptic.success()
                }
            }
            .padding()
            .onAppear { convert() }
        }
    }

    private func convert() {
        guard let value = Double(input) else {
            result = ""
            return
        }
        let converted: Double
        switch category {
        case .length:
            let meters = toMeters(value, from: fromUnit)
            converted = fromMeters(meters, to: toUnit)
        case .weight:
            let kg = toKg(value, from: fromUnit)
            converted = fromKg(kg, to: toUnit)
        case .temperature:
            converted = convertTemp(value, from: fromUnit, to: toUnit)
        case .data:
            let bytes = toBytes(value, from: fromUnit)
            converted = fromBytes(bytes, to: toUnit)
        }
        result = String(format: "%.6g", converted) + " " + units[toUnit]
    }

    private func toMeters(_ v: Double, from: Int) -> Double {
        switch from {
        case 0: return v
        case 1: return v * 1000
        case 2: return v / 100
        case 3: return v / 1000
        case 4: return v * 1609.344
        case 5: return v * 0.9144
        case 6: return v * 0.3048
        case 7: return v * 0.0254
        default: return v
        }
    }

    private func fromMeters(_ m: Double, to: Int) -> Double {
        switch to {
        case 0: return m
        case 1: return m / 1000
        case 2: return m * 100
        case 3: return m * 1000
        case 4: return m / 1609.344
        case 5: return m / 0.9144
        case 6: return m / 0.3048
        case 7: return m / 0.0254
        default: return m
        }
    }

    private func toKg(_ v: Double, from: Int) -> Double {
        switch from {
        case 0: return v
        case 1: return v / 1000
        case 2: return v / 1_000_000
        case 3: return v * 0.45359237
        case 4: return v * 0.028349523125
        case 5: return v * 1000
        default: return v
        }
    }

    private func fromKg(_ kg: Double, to: Int) -> Double {
        switch to {
        case 0: return kg
        case 1: return kg * 1000
        case 2: return kg * 1_000_000
        case 3: return kg / 0.45359237
        case 4: return kg / 0.028349523125
        case 5: return kg / 1000
        default: return kg
        }
    }

    private func convertTemp(_ v: Double, from: Int, to: Int) -> Double {
        var c = v
        if from == 1 { c = (v - 32) * 5 / 9 }
        else if from == 2 { c = v - 273.15 }
        if to == 0 { return c }
        if to == 1 { return c * 9 / 5 + 32 }
        return c + 273.15
    }

    private func toBytes(_ v: Double, from: Int) -> Double {
        switch from {
        case 0: return v
        case 1: return v * 1000
        case 2: return v * 1_000_000
        case 3: return v * 1_000_000_000
        case 4: return v * 1_000_000_000_000
        case 5: return v * 1024
        case 6: return v * 1024 * 1024
        case 7: return v * 1024 * 1024 * 1024
        default: return v
        }
    }

    private func fromBytes(_ b: Double, to: Int) -> Double {
        switch to {
        case 0: return b
        case 1: return b / 1000
        case 2: return b / 1_000_000
        case 3: return b / 1_000_000_000
        case 4: return b / 1_000_000_000_000
        case 5: return b / 1024
        case 6: return b / (1024 * 1024)
        case 7: return b / (1024 * 1024 * 1024)
        default: return b
        }
    }
}
