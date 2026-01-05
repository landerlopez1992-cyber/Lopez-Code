import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  final String chatId;
  final String? projectPath;

  ChatScreen({Key? key, required this.chatId, this.projectPath}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat: $chatId'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              // Aquí irían los mensajes del chat
            ),
          ),
          Container(
            padding: EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.green), // Cambiado a verde
                  onPressed: () {
                    // Acción al enviar el mensaje
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}