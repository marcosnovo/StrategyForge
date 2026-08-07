//
//  ChecklistLibrary.swift
//  StrategyForge
//
//  Curated launch-checklist templates. The iOS one is the "empty repo → App Store" list a
//  shipper runs every time (technical setup, App Store Connect, purchases, ATT order, listing,
//  testing) — the boring steps where launches actually go wrong. A checklist is instantiated as
//  a copy the user owns and ticks off. Content is bilingual inline (like other generated copy)
//  so it doesn't need dozens of loc keys.
//

import Foundation

enum ChecklistTemplateID: String, CaseIterable, Sendable {
    case iosApp, webApp
    var icon: String { self == .iosApp ? "apple.logo" : "globe" }
}

enum ChecklistLibrary {

    static func templateName(_ id: ChecklistTemplateID, es: Bool) -> String {
        switch id {
        case .iosApp: return es ? "Publicar una app iOS" : "Ship an iOS app"
        case .webApp: return es ? "Publicar una app web" : "Ship a web app"
        }
    }

    /// Build a fresh, owned checklist from a template for a given project + language.
    static func make(_ id: ChecklistTemplateID, projectID: UUID?, es: Bool) -> LaunchChecklist {
        LaunchChecklist(name: templateName(id, es: es), projectID: projectID,
                        sections: id == .iosApp ? iosSections(es: es) : webSections(es: es))
    }

    private static func sec(_ en: String, _ es: String, esOn: Bool, _ items: [(String, String, String, String)]) -> ChecklistSection {
        ChecklistSection(title: esOn ? es : en,
                         items: items.map { ChecklistItem(title: esOn ? $0.1 : $0.0,
                                                           hint: esOn ? $0.3 : $0.2) })
    }

    // Tuple: (titleEN, titleES, hintEN, hintES)
    private static func iosSections(es: Bool) -> [ChecklistSection] {
        [
            sec("Technical setup", "Preparación técnica", esOn: es, [
                ("Set up the project with your coding agent", "Configura el proyecto con tu agente", "", ""),
                ("Create the GitHub repo", "Crea el repo de GitHub", "", ""),
                ("Set up the build (Expo/Xcode)", "Configura el build (Expo/Xcode)", "", ""),
                ("Install dependencies", "Instala dependencias", "", ""),
                ("Enable OTA updates", "Activa updates OTA", "Push JS fixes without a full rebuild", "Parches JS sin recompilar entero"),
                ("Integrate Sentry + analytics", "Integra Sentry + analítica", "", ""),
            ]),
            sec("Navigation & foundation", "Navegación y base", esOn: es, [
                ("Native nav bar (Liquid Glass)", "Barra de navegación nativa (Liquid Glass)", "", ""),
                ("Prepare localization", "Prepara la localización", "", ""),
                ("Responsive layout (SafeArea + padding)", "Layout adaptable (SafeArea + padding)", "", ""),
            ]),
            sec("App Store Connect prep", "Preparación App Store Connect", esOn: es, [
                ("Create the Bundle Identifier", "Crea el Bundle Identifier", "", ""),
                ("Create the app in App Store Connect", "Crea la app en App Store Connect", "", ""),
                ("Decide: local storage vs a database", "Decide: almacenamiento local vs base de datos", "Only add a DB if it's social/networked", "Solo añade BD si es social/en red"),
            ]),
            sec("Storage / database", "Almacenamiento / base de datos", esOn: es, [
                ("Create the DB project or save locally", "Crea el proyecto de BD o guarda en local", "", ""),
                ("Connect it (URL + API keys)", "Conéctalo (URL + API keys)", "", ""),
                ("Enable Row Level Security", "Activa Row Level Security", "", ""),
                ("Model the tables", "Modela las tablas", "", ""),
                ("Auth / Apple & Google Sign In", "Auth / Apple y Google Sign In", "Paywall first, then sign up", "Primero paywall, luego registro"),
                ("Edge function to delete a user", "Función edge para borrar usuario", "", ""),
            ]),
            sec("Onboarding", "Onboarding", esOn: es, [
                ("Launch screen", "Pantalla de arranque", "", ""),
                ("ATT prompt FIRST, then init ad SDKs", "Pide ATT PRIMERO, luego inicia SDKs de ads", "Order matters for attribution", "El orden importa para atribución"),
                ("Onboarding steps", "Pasos de onboarding", "", ""),
                ("Notifications", "Notificaciones", "", ""),
                ("Rating modal", "Modal de valoración", "", ""),
                ("Paywall (RevenueCat / Superwall)", "Paywall (RevenueCat / Superwall)", "", ""),
                ("Sign up / Sign in", "Registro / Inicio de sesión", "\"Save your progress\" framing", "Enfoque «guarda tu progreso»"),
                ("Secure password fields", "Campos de contraseña seguros", "textContentType, clear + delay before nav", "textContentType, limpia + retardo antes de navegar"),
            ]),
            sec("Purchases (RevenueCat)", "Compras (RevenueCat)", esOn: es, [
                ("Create in-app products in ASC", "Crea productos in-app en ASC", "", ""),
                ("Create entitlement + offerings", "Crea entitlement + offerings", "", ""),
                ("Packages (monthly / yearly / lifetime)", "Paquetes (mensual / anual / vitalicio)", "", ""),
                ("Implement purchase + Restore", "Implementa compra + Restaurar", "", ""),
                ("Store entitlement server-side", "Guarda el entitlement en servidor", "", ""),
                ("Subscription guard on protected screens", "Guard de suscripción en pantallas protegidas", "", ""),
                ("Cancel flow with a special offer", "Flujo de cancelación con oferta", "", ""),
            ]),
            sec("App Store listing", "Ficha en App Store", esOn: es, [
                ("Name, subtitle, keywords", "Nombre, subtítulo, keywords", "", ""),
                ("Screenshots (iPhone / iPad)", "Capturas (iPhone / iPad)", "", ""),
                ("Description + promo text (SEO)", "Descripción + texto promo (SEO)", "", ""),
                ("Privacy policy + support URL", "Política de privacidad + URL de soporte", "", ""),
                ("Localizations", "Localizaciones", "", ""),
                ("Review notes", "Notas para revisión", "", ""),
            ]),
            sec("Assets", "Recursos", esOn: es, [
                ("App icon", "Icono de la app", "", ""),
                ("Translate all text (CFBundleLocalizations)", "Traduce todo el texto (CFBundleLocalizations)", "", ""),
                ("Privacy / age rating sub-pages", "Sub-páginas de privacidad / edad", "", ""),
                ("Widgets", "Widgets", "", ""),
            ]),
            sec("Build & testing", "Build y pruebas", esOn: es, [
                ("Create the build", "Crea el build", "", ""),
                ("Test sign in / sign out", "Prueba inicio / cierre de sesión", "", ""),
                ("Test purchases + Restore", "Prueba compras + Restaurar", "", ""),
                ("Test on iPad and Pro models", "Prueba en iPad y modelos Pro", "", ""),
                ("Test notifications", "Prueba notificaciones", "", ""),
            ]),
        ]
    }

    private static func webSections(es: Bool) -> [ChecklistSection] {
        [
            sec("Setup", "Preparación", esOn: es, [
                ("Create the repo + CI", "Crea el repo + CI", "", ""),
                ("Set env vars & secrets", "Configura variables y secretos", "", ""),
                ("Error tracking + analytics", "Seguimiento de errores + analítica", "", ""),
            ]),
            sec("Data & auth", "Datos y auth", esOn: es, [
                ("Database + migrations", "Base de datos + migraciones", "", ""),
                ("Row Level Security", "Row Level Security", "", ""),
                ("Auth (email / OAuth)", "Auth (email / OAuth)", "", ""),
            ]),
            sec("Launch", "Lanzamiento", esOn: es, [
                ("Custom domain + HTTPS", "Dominio propio + HTTPS", "", ""),
                ("Privacy policy + terms", "Política de privacidad + términos", "", ""),
                ("SEO meta + social cards", "Meta SEO + tarjetas sociales", "", ""),
                ("Deploy to production", "Despliega a producción", "", ""),
                ("Smoke-test the live site", "Smoke-test del sitio en vivo", "", ""),
            ]),
        ]
    }
}
