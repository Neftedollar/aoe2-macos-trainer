import AppKit
import SwiftUI

struct HUDCalibrationView: View {
    let image: NSImage
    let onSave: (HUDLayout) -> Void
    let onCancel: () -> Void

    @State private var selectedField: HUDField = .clock
    @State private var draft: HUDLayout

    init(image: NSImage, layout: HUDLayout,
         onSave: @escaping (HUDLayout) -> Void,
         onCancel: @escaping () -> Void) {
        self.image = image
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: layout)
    }

    private var previewSize: CGSize {
        let scale = min(880 / max(image.size.width, 1), 520 / max(image.size.height, 1))
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройка распознавания HUD")
                .font(.title2.bold())
            Text("Выбери показатель и выдели мышью прямоугольник ТОЛЬКО вокруг цифр на скриншоте. Повтори для нужных показателей. Оверлей при захвате исключён.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Показатель", selection: $selectedField) {
                ForEach(HUDField.allCases) { field in
                    Text(field.title).tag(field)
                }
            }
            .pickerStyle(.segmented)

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: previewSize.width, height: previewSize.height)

                ForEach(HUDField.allCases) { field in
                    if let region = draft.regions[field], region.isValid {
                        Rectangle()
                            .stroke(field == selectedField ? .yellow : .green, lineWidth: 2)
                            .background((field == selectedField ? Color.yellow : Color.green).opacity(0.10))
                            .frame(
                                width: region.width * previewSize.width,
                                height: region.height * previewSize.height
                            )
                            .position(
                                x: (region.x + region.width / 2) * previewSize.width,
                                y: (region.y + region.height / 2) * previewSize.height
                            )
                    }
                }

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { gesture in updateRegion(start: gesture.startLocation, end: gesture.location) }
                    )
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .border(Color.secondary.opacity(0.5))

            HStack {
                Text("Настроено: \(draft.regions.filter { $0.value.isValid }.count) из 6")
                    .font(.callout)
                Button("Очистить выбранную") {
                    draft.regions.removeValue(forKey: selectedField)
                }
                Spacer()
                Button("Отмена", action: onCancel)
                Button("Сохранить и включить OCR") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.hasRegions)
            }
        }
        .padding(18)
        .frame(width: 930)
    }

    private func updateRegion(start: CGPoint, end: CGPoint) {
        let x1 = min(max(start.x / previewSize.width, 0), 1)
        let y1 = min(max(start.y / previewSize.height, 0), 1)
        let x2 = min(max(end.x / previewSize.width, 0), 1)
        let y2 = min(max(end.y / previewSize.height, 0), 1)
        let rect = NormalizedHUDRect(
            x: min(x1, x2), y: min(y1, y2),
            width: abs(x2 - x1), height: abs(y2 - y1)
        )
        if rect.isValid { draft.regions[selectedField] = rect }
    }
}
