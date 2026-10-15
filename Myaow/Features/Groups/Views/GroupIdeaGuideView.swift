import SwiftUI

/// Guided starting points, not an AI-generated or remotely shared idea board.
struct GroupIdeaGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let canCreate: Bool
    let choose: (String) -> Void
    private let prompts: [(String, String, String, String)] = [
        ("lightbulb", "Abrir posibilidades", "¿Qué haríamos si lo intentáramos de otra manera?", "Reunir tres alternativas para el siguiente paso"),
        ("scope", "Elegir una dirección", "¿Qué opción aporta más valor con el esfuerzo que tenemos?", "Comparar las propuestas y acordar una dirección"),
        ("hammer", "Hacer una prueba pequeña", "¿Cómo comprobamos la idea sin construir todo?", "Preparar una prueba pequeña de la idea elegida"),
        ("bubble.left.and.bubble.right", "Aprender del resultado", "¿Qué funcionó, qué estorbó y qué cambiamos?", "Revisar el resultado y acordar la siguiente mejora")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    GroupEyebrow(title: "Del chat a la acción")
                    Text("Las buenas ideas\nse construyen juntos.").font(.system(size: 29, weight: .semibold)).tracking(-0.5)
                    Text("Usen estas preguntas para conversar. Cuando una propuesta tenga sentido, conviértanla en una tarea con responsable y fecha.")
                        .font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                    ForEach(prompts, id: \.0) { symbol, title, question, task in
                        GroupPanel {
                            VStack(alignment: .leading, spacing: 14) {
                                Label(title, systemImage: symbol).font(.headline).foregroundStyle(MyaowColor.orange)
                                Text(question).font(.title3.weight(.medium))
                                Button { dismiss(); choose(task) } label: {
                                    Label("Preparar tarea", systemImage: "plus.circle").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                                }.tint(MyaowColor.orange).disabled(!canCreate)
                            }
                        }
                    }
                    if !canCreate { Text("Un administrador puede convertir la propuesta en tarea según los permisos de este grupo.").font(.caption).foregroundStyle(MyaowColor.textSecondary) }
                }.padding(24)
            }.background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
                .navigationTitle("Activar ideas").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.tint(MyaowColor.orange) } }
        }.preferredColorScheme(.dark)
    }
}
