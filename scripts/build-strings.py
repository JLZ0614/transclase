#!/usr/bin/env python3
"""Builds every <lang>.lproj/Localizable.strings from translations/*.json.

Any key missing from a language falls back to English, so a non-Chinese UI can
never show a stray Chinese string.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "translations/source.json"
LANGS = ["en", "es", "fr", "de", "ja", "ko"]

EXTRA = {
    "笔记": {"en": "Note", "es": "Nota", "fr": "Note", "de": "Notiz", "ja": "メモ", "ko": "메모"},
    "语音笔记": {"en": "Voice notes", "es": "Notas de voz", "fr": "Notes vocales",
                 "de": "Sprachnotizen", "ja": "音声メモ", "ko": "음성 메모"},
    "仅转写": {"en": "Transcription only", "es": "Solo transcripción", "fr": "Transcription seule",
               "de": "Nur Transkription", "ja": "文字起こしのみ", "ko": "받아쓰기만"},
    "正在听写…": {"en": "Dictating…", "es": "Dictando…", "fr": "Dictée en cours…",
                  "de": "Diktiert…", "ja": "音声入力中…", "ko": "받아쓰는 중…"},
    "开始下载": {"en": "Start download", "es": "Descargar", "fr": "Télécharger",
                 "de": "Laden", "ja": "ダウンロード", "ko": "다운로드"},
    "下载中…": {"en": "Downloading…", "es": "Descargando…", "fr": "Téléchargement…",
                "de": "Wird geladen…", "ja": "ダウンロード中…", "ko": "다운로드 중…"},
    "高质量翻译": {"en": "High-quality translation", "es": "Traducción de alta calidad",
                   "fr": "Traduction de haute qualité", "de": "Übersetzung in hoher Qualität",
                   "ja": "高品質翻訳", "ko": "고품질 번역"},
    "测试 API 连接": {"en": "Test API connection", "es": "Probar conexión API",
                      "fr": "Tester la connexion API", "de": "API-Verbindung testen",
                      "ja": "API 接続をテスト", "ko": "API 연결 테스트"},
    "翻译失败，点按重试": {"en": "Translation failed — tap to retry", "es": "Error de traducción: toca para reintentar",
                          "fr": "Échec de la traduction — toucher pour réessayer",
                          "de": "Übersetzung fehlgeschlagen – zum Wiederholen tippen",
                          "ja": "翻訳に失敗 — タップで再試行", "ko": "번역 실패 — 탭하여 다시 시도"},
    "翻译引擎尚未就绪": {"en": "Translation engine is not ready yet", "es": "El motor de traducción aún no está listo",
                         "fr": "Le moteur de traduction n'est pas encore prêt",
                         "de": "Die Übersetzungs-Engine ist noch nicht bereit",
                         "ja": "翻訳エンジンの準備ができていません", "ko": "번역 엔진이 아직 준비되지 않았습니다"},
    "%d 段": {"en": "%d segments", "es": "%d segmentos", "fr": "%d segments",
              "de": "%d Abschnitte", "ja": "%d 段落", "ko": "%d개 구간"},
    "下载识别模型 %d%%": {
        "en": "Downloading speech model %d%%", "es": "Descargando modelo %d%%",
        "fr": "Téléchargement du modèle %d%%", "de": "Sprachmodell wird geladen %d%%",
        "ja": "音声モデルをダウンロード中 %d%%", "ko": "음성 모델 다운로드 중 %d%%",
    },
    "上课时点「总结」，或打开自动总结（1–10 分钟）。": {
        "en": "Press Summarise during a lecture, or enable auto-summary (1–10 min).",
        "es": "Pulsa Resumir durante la clase o activa el resumen automático (1–10 min).",
        "fr": "Appuyez sur Résumer pendant le cours, ou activez le résumé automatique (1–10 min).",
        "de": "Tippe während der Vorlesung auf Zusammenfassen oder aktiviere die automatische Zusammenfassung (1–10 Min.).",
        "ja": "授業中に「要約」を押すか、自動要約（1〜10分）をオンにしてください。",
        "ko": "수업 중 '요약'을 누르거나 자동 요약(1~10분)을 켜세요.",
    },
    "也可以直接在下面提问。": {
        "en": "You can also ask questions below.",
        "es": "También puedes preguntar abajo.",
        "fr": "Vous pouvez aussi poser une question ci-dessous.",
        "de": "Du kannst auch unten Fragen stellen.",
        "ja": "下の欄から質問もできます。",
        "ko": "아래에서 질문할 수도 있습니다.",
    },
    "已下载的模型": {
        "en": "Downloaded models", "es": "Modelos descargados", "fr": "Modèles téléchargés",
        "de": "Geladene Modelle", "ja": "ダウンロード済みモデル", "ko": "다운로드한 모델",
    },
    "重启失败，请手动退出后重新打开": {
        "en": "Could not relaunch — quit and reopen the app manually.",
        "es": "No se pudo reiniciar: cierra y vuelve a abrir la app.",
        "fr": "Échec du redémarrage : quittez et rouvrez l'app.",
        "de": "Neustart fehlgeschlagen – bitte die App manuell beenden und neu öffnen.",
        "ja": "再起動できませんでした。アプリを終了して開き直してください。",
        "ko": "재시작하지 못했습니다. 앱을 종료한 뒤 다시 열어 주세요.",
    },
    "繁體中文": {
        "en": "Traditional Chinese", "es": "Chino tradicional", "fr": "Chinois traditionnel",
        "de": "Traditionelles Chinesisch", "ja": "繁体字中国語", "ko": "중국어 번체",
    },
    "外观": {
        "en": "Appearance", "es": "Apariencia", "fr": "Apparence",
        "de": "Darstellung", "ja": "外観", "ko": "모양",
    },
    "浅色": {"en": "Light", "es": "Claro", "fr": "Clair", "de": "Hell", "ja": "ライト", "ko": "라이트"},
    "深色": {"en": "Dark", "es": "Oscuro", "fr": "Sombre", "de": "Dunkel", "ja": "ダーク", "ko": "다크"},
    "刚刚": {"en": "Just now", "es": "Ahora mismo", "fr": "À l'instant",
             "de": "Gerade eben", "ja": "たった今", "ko": "방금"},
    "打开": {"en": "Open", "es": "Abrir", "fr": "Ouvrir", "de": "Öffnen", "ja": "開く", "ko": "열기"},
    "每 %d 分钟": {"en": "Every %d min", "es": "Cada %d min", "fr": "Toutes les %d min",
                   "de": "Alle %d Min.", "ja": "%d 分ごと", "ko": "%d분마다"},
    "当前 %d 段内容会被删除，且无法恢复。想留档的话先导出。": {
        "en": "All %d segments will be deleted and cannot be recovered. Export first if you want to keep them.",
        "es": "Se eliminarán los %d segmentos y no se podrán recuperar. Exporta primero si quieres conservarlos.",
        "fr": "Les %d segments seront supprimés sans possibilité de récupération. Exportez avant si vous voulez les garder.",
        "de": "Alle %d Abschnitte werden gelöscht und können nicht wiederhergestellt werden. Exportiere vorher, wenn du sie behalten willst.",
        "ja": "%d 件の段落が削除され、元に戻せません。残す場合は先に書き出してください。",
        "ko": "%d개 구간이 삭제되며 복구할 수 없습니다. 보관하려면 먼저 내보내세요.",
    },
    "顶部菜单栏会在下次启动时同步。": {
        "en": "The menu bar updates on next launch.",
        "es": "La barra de menús se actualizará al reiniciar.",
        "fr": "La barre des menus sera mise à jour au prochain lancement.",
        "de": "Die Menüleiste wird beim nächsten Start aktualisiert.",
        "ja": "メニューバーは次回起動時に更新されます。",
        "ko": "메뉴 막대는 다음 실행 시 업데이트됩니다.",
    },
}

keys = json.loads(SRC.read_text()) + list(EXTRA)
base = json.loads((ROOT / "translations/en.json").read_text())

missing_report = {}
for lang in LANGS:
    path = ROOT / f"translations/{lang}.json"
    if not path.exists():
        print(f"!! missing {path}")
        sys.exit(1)
    table = json.loads(path.read_text())

    for k, values in EXTRA.items():
        table[k] = values[lang]
    missing = [k for k in keys if k not in table or not str(table[k]).strip()]
    if missing:
        missing_report[lang] = len(missing)
        for k in missing:
            table[k] = base.get(k, k)

    lines = ['/* Generated by scripts/build-strings.py — do not edit by hand. */', ""]
    for k in keys:
        value = str(table[k]).replace("\\", "\\\\").replace('"', '\\"')
        key = k.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'"{key}" = "{value}";')
    out = ROOT / f"Transclase/{lang}.lproj/Localizable.strings"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
    print(f"{lang}: {len(keys)} entries -> {out.relative_to(ROOT)}")

if missing_report:
    print("filled from English:", missing_report)
