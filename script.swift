import SwiftUI

@main
struct ModernApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 300, height: 200)
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Bienvenido")
                .font(.title)
                .foregroundColor(.white)
            
            Button(action: {
                // Acción del botón
            }) {
                Text("Acción")
                    .fontWeight(.bold)
                    .frame(width: 120, height: 40)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("Favorito")
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(
            LinearGradient(gradient: Gradient(colors: [.purple, .blue]), startPoint: .top, endPoint: .bottom)
        )
        .cornerRadius(15)
        .shadow(radius: 10)
    }
}
