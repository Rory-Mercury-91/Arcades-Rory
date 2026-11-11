// Feuille de score. La table en ligne est propre à cette application.
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .build(tauri::generate_context!())
        .expect("erreur au lancement de Yams")
        .run(|app, event| {
            if let tauri::RunEvent::Resumed = event {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.eval("window.dispatchEvent(new Event('yams-resume'))");
                }
            }
        });
}
