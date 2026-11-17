import { initializeApp, type FirebaseApp } from 'firebase/app'
import { getAuth, type Auth } from 'firebase/auth'
import { getFirestore, type Firestore } from 'firebase/firestore'

/**
 * Config Firebase Web para el panel admin.
 * Completa con las keys del app Web en Firebase Console
 * (Project settings → Your apps → Web), o deja vacío para modo demo.
 */
const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY ?? '',
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN ?? 'voryxel-code.firebaseapp.com',
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID ?? 'voryxel-code',
  storageBucket:
    import.meta.env.VITE_FIREBASE_STORAGE_BUCKET ?? 'voryxel-code.firebasestorage.app',
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID ?? '213137346280',
  appId: import.meta.env.VITE_FIREBASE_APP_ID ?? '',
}

export const firebaseConfigured =
  Boolean(firebaseConfig.apiKey) &&
  Boolean(firebaseConfig.appId) &&
  !String(firebaseConfig.apiKey).includes('YOUR_')

let app: FirebaseApp | null = null
let auth: Auth | null = null
let db: Firestore | null = null

export function getFirebase() {
  if (!firebaseConfigured) {
    return { app: null, auth: null, db: null }
  }
  if (!app) {
    app = initializeApp(firebaseConfig)
    auth = getAuth(app)
    db = getFirestore(app)
  }
  return { app, auth, db }
}
