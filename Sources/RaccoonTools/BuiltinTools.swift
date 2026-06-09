import Foundation
import AppKit

/// Default system prompts for LLM tools
enum LLMToolPrompts {
    static let defaults: [String: String] = [
        "translate": """
            You are a translator. Translate the given word or phrase to the requested language.
            Provide:
            1. The main translation
            2. 2-3 alternative translations with brief context (formal/informal/literal)
            Format clearly, one per line.
            """,
        "rephrase mail": """
            You are a professional email writer. Rephrase the given text as a clear, professional email.
            Keep it concise and polite. Return only the rephrased text, no explanations.
            """,
        "rephrase msg": """
            You are a casual messaging assistant. Rephrase the given text as a friendly, concise message.
            Keep it natural and conversational. Return only the rephrased text.
            """,
        "rephrase teams": """
            You are a professional Teams/Slack message writer. Rephrase the given text as a clear,
            professional but not overly formal workplace message. Return only the rephrased text.
            """,
        "rephrase idea": """
            You are a writing assistant. Take the rough idea provided and rephrase it clearly and concisely.
            Structure the thought, improve clarity, keep the original intent. Return only the rephrased text.
            """,
        "def": """
            You are a dictionary. Give a clear, concise definition of the word or phrase.
            Include: part of speech, 1-2 definitions, and a brief example. Be concise.
            """,
        "explain": """
            You are a concise explainer. Explain the given concept or phrase in 2-4 sentences.
            Be clear, accurate, and accessible. No fluff.
            """,
        "summarize txt": """
            Summarize the following text concisely. Give the key points in a structured format.
            Be brief but capture all important information.
            """,
        "summarize video": """
            Summarize the following video transcript concisely. Give the key points, main topics discussed,
            and any conclusions. Be brief but comprehensive.
            """,
        "summarize link": """
            Summarize the following webpage content concisely. Give the key points and main information.
            Ignore navigation, ads, and boilerplate. Be brief but capture all important information.
            """,
        "summarize file": """
            Summarize the following file content concisely. Give the key points in a structured format.
            Be brief but capture all important information.
            """,
        "file qa": """
            Answer the user's question based on the file content provided.
            Be concise and accurate. Just answer directly, no special formatting.
            """,
        "fix grammar": """
            Fix all grammar and spelling mistakes in the following text.
            Return only the corrected text, no explanations. Keep the original tone and style.
            """,
        "rephrase formal": """
            Rephrase the following text in a formal, professional tone.
            Return only the rephrased text, no explanations.
            """,
        "rephrase casual": """
            Rephrase the following text in a casual, friendly tone.
            Return only the rephrased text, no explanations.
            """,
        "subject": """
            Generate a concise, professional email subject line for the following email text.
            Return only the subject line, nothing else.
            """,
        "color palette": """
            Given a hex color, generate a harmonious 5-color palette.
            Return EXACTLY 5 lines, one per color, in this strict format:
            #XXXXXX|Name|Role
            Example: #FF5733|Coral Red|Primary
            No other text, no explanations, just the 5 lines.
            """,
        "free": """
            You are a contextual writing assistant. The user selected text in their app and wants to interact with it.

            Determine if the user wants to:
            1. EDIT the text (rephrase, translate, fix, shorten, correct, replace, rewrite, etc.)
            2. ASK a question about the text (define, explain, what language, synonyms, analyze, etc.)

            For EDIT requests: respond with EXACTLY "EDIT:" followed by the modified text. Nothing else after EDIT:.
            For QUESTION requests: respond with EXACTLY "ANSWER:" followed by your concise answer.
            Your reply MUST start with "EDIT:" or "ANSWER:" as the very first characters — no preamble.

            When editing, return ONLY the modified text after "EDIT:". No explanations, no commentary.
            When answering, be concise and helpful.
            Preserve the original formatting unless asked otherwise.
            """,
    ]
}

func registerBuiltinTools() {
    let registry = ToolRegistry.shared
    let settings = SettingsManager.shared

    // ============================================================
    // MARK: - GET tools
    // ============================================================

    // get youtube sound
    registry.register(ToolCommand(
        path: ["get", "youtube", "sound"],
        description: "Download audio from a YouTube video (MP3)",
        parameterName: "url",
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let ytdlp = try await ensureDep("yt-dlp", brew: "yt-dlp")
            return try await shellExec(ytdlp, args: [
                "-x", "--audio-format", "mp3",
                "-o", "\(settings.outputFolder)/%(title)s.%(ext)s", url
            ])
        }
    ))

    // get youtube video
    registry.register(ToolCommand(
        path: ["get", "youtube", "video"],
        description: "Download a YouTube video",
        parameterName: "url",
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let ytdlp = try await ensureDep("yt-dlp", brew: "yt-dlp")
            return try await shellExec(ytdlp, args: [
                "-o", "\(settings.outputFolder)/%(title)s.%(ext)s", url
            ])
        }
    ))

    // get youtube transcript → .txt
    registry.register(ToolCommand(
        path: ["get", "youtube", "transcript"],
        description: "Download subtitles as .txt from a YouTube video",
        parameterName: "url",
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let ytdlp = try await ensureDep("yt-dlp", brew: "yt-dlp")
            let output = settings.outputFolder

            // Download subtitles (VTT format)
            let result = try await shellExec(ytdlp, args: [
                "--write-auto-sub", "--sub-lang", "en",
                "--skip-download",
                "-o", "\(output)/%(title)s", url
            ])

            // Convert VTT files to plain .txt
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(atPath: output) {
                for file in files where file.hasSuffix(".vtt") {
                    let vttPath = "\(output)/\(file)"
                    if let content = try? String(contentsOfFile: vttPath, encoding: .utf8) {
                        let txt = vttToPlainText(content)
                        let txtPath = vttPath.replacingOccurrences(of: ".vtt", with: ".txt")
                        try? txt.write(toFile: txtPath, atomically: true, encoding: .utf8)
                        try? fm.removeItem(atPath: vttPath)
                    }
                }
            }

            return result.contains("Error") ? result : "Transcript saved as .txt to \(output)"
        }
    ))

    // get transcript file (Whisper)
    registry.register(ToolCommand(
        path: ["get", "file", "transcript"],
        description: "Transcribe audio/video file with Whisper AI",
        parameterName: "path",
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: please provide a file path" }
            let whisper = try await ensureDep("whisper-cpp", brew: "whisper-cpp")
            let output = settings.outputFolder
            let expandedPath = (filePath as NSString).expandingTildeInPath

            guard FileManager.default.fileExists(atPath: expandedPath) else {
                return "Error: file not found at \(expandedPath)"
            }

            let modelDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/whisper").path
            try? FileManager.default.createDirectory(atPath: modelDir, withIntermediateDirectories: true)
            let modelPath = "\(modelDir)/ggml-base.bin"

            if !FileManager.default.fileExists(atPath: modelPath) {
                let modelURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
                _ = try await shellExec("/usr/bin/curl", args: ["-L", "-o", modelPath, modelURL])
            }

            let baseName = (expandedPath as NSString).lastPathComponent
                .replacingOccurrences(of: ".", with: "_")
            let result = try await shellExec(whisper, args: [
                "-m", modelPath, "-f", expandedPath,
                "-otxt", "-of", "\(output)/\(baseName)"
            ])
            return result.isEmpty ? "Transcription saved to \(output)/\(baseName).txt" : result
        }
    ))

    // get txt link
    registry.register(ToolCommand(
        path: ["get", "link", "txt"],
        description: "Save a webpage as plain text",
        parameterName: "url",
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a URL" }
            let result = try await shellExec("/usr/bin/curl", args: ["-sL", url])
            let text = result
                .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = URL(string: url)?.host ?? "page"
            let outputPath = "\(settings.outputFolder)/\(filename).txt"
            try text.write(toFile: outputPath, atomically: true, encoding: .utf8)
            return "Saved to \(outputPath) (\(text.count) chars)"
        }
    ))

    // ============================================================
    // MARK: - GET FILE tools (extract)
    // ============================================================

    // get file path — show full path of a file
    registry.register(ToolCommand(
        path: ["get", "file", "path"],
        description: "Get the full path of a file (drag & drop)",
        parameterName: "file",
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: drag & drop a file" }
            let p = (filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: p) else { return "Error: file not found" }
            return p
        }
    ))

    // get file text — extract raw text from PDF/docx/txt
    registry.register(ToolCommand(
        path: ["get", "file", "text"],
        description: "Extract text from PDF/docx/image/txt (drag & drop, OCR auto)",
        parameterName: "file",
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: drag & drop a file" }
            let p = (filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: p) else { return "Error: file not found" }

            let ext = (p as NSString).pathExtension.lowercased()
            if ext == "pdf" {
                // Use macOS built-in PDFKit via python
                let script = "import sys; from Quartz import PDFDocument; from Foundation import NSURL; d=PDFDocument.alloc().initWithURL_(NSURL.fileURLWithPath_(sys.argv[1])); print(''.join([d.pageAtIndex_(i).string() or '' for i in range(d.pageCount())]))"
                let text = try await shellExec(PythonEnv.shared.pythonPath, args: ["-c", script, p])
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if ext == "docx" {
                // Extract text from docx via python zipfile
                let script = """
                import zipfile, xml.etree.ElementTree as ET, sys
                z=zipfile.ZipFile(sys.argv[1])
                xml=z.read('word/document.xml')
                root=ET.fromstring(xml)
                ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
                print('\\n'.join([''.join([t.text or '' for t in p.findall('.//w:t',ns)]) for p in root.findall('.//w:p',ns)]))
                """
                let text = try await shellExec(PythonEnv.shared.pythonPath, args: ["-c", script, p])
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if ["jpg", "jpeg", "png", "tiff", "bmp", "gif", "heic", "webp"].contains(ext) {
                // OCR via macOS Vision framework
                let script = """
                import sys, objc
                from Foundation import NSURL
                import Vision, Quartz
                url = NSURL.fileURLWithPath_(sys.argv[1])
                src = Quartz.CGImageSourceCreateWithURL(url, None)
                if not src: print("Error: cannot open image"); sys.exit(1)
                img = Quartz.CGImageSourceCreateImageAtIndex(src, 0, None)
                req = Vision.VNRecognizeTextRequest.alloc().init()
                req.setRecognitionLevel_(1)
                handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(img, None)
                handler.performRequests_error_([req], None)
                for obs in req.results() or []:
                    print(obs.topCandidates_(1)[0].string())
                """
                let text = try await shellExec(PythonEnv.shared.pythonPath, args: ["-c", script, p])
                let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return result.isEmpty ? "No text found in image" : result
            } else {
                // Plain text
                guard let text = try? String(contentsOfFile: p, encoding: .utf8) else {
                    return "Error: could not read file as text"
                }
                return text
            }
        }
    ))

    // get file metadata — name, size, dates, MIME type
    registry.register(ToolCommand(
        path: ["get", "file", "metadata"],
        description: "Show file metadata (drag & drop)",
        parameterName: "file",
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: drag & drop a file" }
            let p = (filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: p) else { return "Error: file not found" }

            let name = (p as NSString).lastPathComponent
            let size = attrs[.size] as? Int64 ?? 0
            let created = (attrs[.creationDate] as? Date)?.formatted() ?? "unknown"
            let modified = (attrs[.modificationDate] as? Date)?.formatted() ?? "unknown"
            let type = attrs[.type] as? FileAttributeType

            // Get MIME type
            let mimeResult = try? await shellExec("/usr/bin/file", args: ["--mime-type", "-b", p])
            let mime = mimeResult?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

            let sizeStr: String
            if size > 1_000_000_000 { sizeStr = String(format: "%.1f GB", Double(size) / 1e9) }
            else if size > 1_000_000 { sizeStr = String(format: "%.1f MB", Double(size) / 1e6) }
            else if size > 1_000 { sizeStr = String(format: "%.1f KB", Double(size) / 1e3) }
            else { sizeStr = "\(size) B" }

            return """
            Name: \(name)
            Size: \(sizeStr)
            Type: \(mime)
            Created: \(created)
            Modified: \(modified)
            Kind: \(type == .typeDirectory ? "Directory" : "File")
            Path: \(p)
            """
        }
    ))

    // get file links — extract URLs from PDF or HTML
    registry.register(ToolCommand(
        path: ["get", "file", "links"],
        description: "Extract all URLs from a file (drag & drop)",
        parameterName: "file",
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: drag & drop a file" }
            let p = (filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            guard let data = FileManager.default.contents(atPath: p) else { return "Error: cannot read file" }
            let content = String(data: data, encoding: .utf8) ?? ""

            // Regex to find URLs
            let pattern = #"https?://[^\s<>\"'\)\]\}]+"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return "Error: regex failed" }
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)
            let urls = matches.compactMap { Range($0.range, in: content).map { String(content[$0]) } }
            let unique = Array(Set(urls)).sorted()

            if unique.isEmpty { return "No URLs found" }
            return unique.joined(separator: "\n")
        }
    ))

    // ============================================================
    // MARK: - FILE transform tools
    // ============================================================

    // file to pdf
    registry.register(ToolCommand(
        path: ["file", "to", "pdf"],
        description: "Convert file or image folder to PDF (drag & drop)",
        parameterName: "file or folder",
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: drag & drop a file or folder" }
            let p = (filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            let fm = FileManager.default
            guard fm.fileExists(atPath: p) else { return "Error: file not found" }
            let baseName = ((p as NSString).lastPathComponent as NSString).deletingPathExtension
            let outputPath = "\(settings.outputFolder)/\(baseName).pdf"

            var isDir: ObjCBool = false
            fm.fileExists(atPath: p, isDirectory: &isDir)

            if isDir.boolValue {
                // Folder of images → merge into one PDF
                let imageExts = Set(["jpg", "jpeg", "png", "tiff", "bmp", "gif", "heic", "webp"])
                guard let files = try? fm.contentsOfDirectory(atPath: p) else { return "Error: can't read folder" }
                let images = files.filter { imageExts.contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
                guard !images.isEmpty else { return "Error: no images found in folder" }

                let script = """
                from Quartz import *; from Foundation import *
                import sys, os
                folder = sys.argv[1]; output = sys.argv[2]
                exts = {'.jpg','.jpeg','.png','.tiff','.bmp','.gif','.heic','.webp'}
                files = sorted([f for f in os.listdir(folder) if os.path.splitext(f)[1].lower() in exts])
                ctx = None
                for f in files:
                    url = NSURL.fileURLWithPath_(os.path.join(folder, f))
                    src = CGImageSourceCreateWithURL(url, None)
                    if not src: continue
                    img = CGImageSourceCreateImageAtIndex(src, 0, None)
                    if not img: continue
                    w, h = CGImageGetWidth(img), CGImageGetHeight(img)
                    if ctx is None:
                        ctx = CGPDFContextCreateWithURL(NSURL.fileURLWithPath_(output), CGRectMake(0,0,w,h), None)
                    CGPDFContextBeginPage(ctx, None)
                    CGContextDrawImage(ctx, CGRectMake(0,0,w,h), img)
                    CGPDFContextEndPage(ctx)
                if ctx: CGPDFContextClose(ctx)
                print(f'{len(files)} images merged')
                """
                let result = try await shellExec(PythonEnv.shared.pythonPath, args: ["-c", script, p, outputPath])
                return "\(result.trimmingCharacters(in: .whitespacesAndNewlines)) → \(outputPath)"
            }

            let ext = (p as NSString).pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "tiff", "bmp", "gif", "heic", "webp"].contains(ext) {
                let script = """
                from Quartz import *; from Foundation import *
                import sys
                url = NSURL.fileURLWithPath_(sys.argv[1])
                src = CGImageSourceCreateWithURL(url, None)
                img = CGImageSourceCreateImageAtIndex(src, 0, None)
                w, h = CGImageGetWidth(img), CGImageGetHeight(img)
                ctx = CGPDFContextCreateWithURL(NSURL.fileURLWithPath_(sys.argv[2]), CGRectMake(0,0,w,h), None)
                CGPDFContextBeginPage(ctx, None); CGContextDrawImage(ctx, CGRectMake(0,0,w,h), img)
                CGPDFContextEndPage(ctx); CGPDFContextClose(ctx)
                """
                _ = try await shellExec(PythonEnv.shared.pythonPath, args: ["-c", script, p, outputPath])
            } else if ["docx", "doc", "rtf", "rtfd", "txt", "html", "md"].contains(ext) {
                // Use NSAttributedString → PDF via Python (textutil doesn't support PDF output)
                var inputPath = p
                if ext == "md" {
                    // Convert markdown to HTML first
                    let md = try String(contentsOfFile: p, encoding: .utf8)
                    let htmlPath = NSTemporaryDirectory() + "\(baseName).html"
                    let html = "<html><body style='font-family:system-ui;padding:40px;max-width:800px;margin:auto'>\(md)</body></html>"
                    try html.write(toFile: htmlPath, atomically: true, encoding: .utf8)
                    inputPath = htmlPath
                }
                let script = """
                from Cocoa import *; from Quartz import *; import sys
                url = NSURL.fileURLWithPath_(sys.argv[1])
                r = NSAttributedString.alloc().initWithURL_options_documentAttributes_error_(url, {}, None, None)
                if r is None or r[0] is None: print('Error: cannot read file'); sys.exit(1)
                attrStr = r[0]
                pi = NSPrintInfo.sharedPrintInfo()
                margin = 72
                pi.setTopMargin_(margin); pi.setBottomMargin_(margin)
                pi.setLeftMargin_(margin); pi.setRightMargin_(margin)
                ps = pi.paperSize()
                w = ps.width - margin * 2; pageH = ps.height - margin * 2
                ts = NSTextStorage.alloc().initWithAttributedString_(attrStr)
                lm = NSLayoutManager.alloc().init()
                tc = NSTextContainer.alloc().initWithSize_(NSMakeSize(w, 1e7))
                tc.setLineFragmentPadding_(0)
                lm.addTextContainer_(tc); ts.addLayoutManager_(lm)
                lm.glyphRangeForTextContainer_(tc)
                totalH = lm.usedRectForTextContainer_(tc).size.height
                pages = int(totalH / pageH) + 1
                pdfData = NSMutableData.alloc().init()
                consumer = CGDataConsumerCreateWithCFData(pdfData)
                ctx = CGPDFContextCreate(consumer, CGRectMake(0, 0, ps.width, ps.height), None)
                for page in range(pages):
                    CGPDFContextBeginPage(ctx, None)
                    CGContextTranslateCTM(ctx, margin, margin)
                    yOff = page * pageH
                    dr = lm.glyphRangeForBoundingRect_inTextContainer_(NSMakeRect(0, yOff, w, pageH), tc)
                    nsCtx = NSGraphicsContext.graphicsContextWithCGContext_flipped_(ctx, True)
                    NSGraphicsContext.setCurrentContext_(nsCtx)
                    CGContextScaleCTM(ctx, 1, -1); CGContextTranslateCTM(ctx, 0, -pageH)
                    lm.drawBackgroundForGlyphRange_atPoint_(dr, NSMakePoint(0, -yOff))
                    lm.drawGlyphsForGlyphRange_atPoint_(dr, NSMakePoint(0, -yOff))
                    CGPDFContextEndPage(ctx)
                CGPDFContextClose(ctx)
                pdfData.writeToFile_atomically_(sys.argv[2], True)
                """
                _ = try await shellExec(PythonEnv.shared.pythonPath, args: ["-c", script, inputPath, outputPath])
                if ext == "md" { try? fm.removeItem(atPath: inputPath) }
                guard fm.fileExists(atPath: outputPath) else { return "Error: PDF creation failed" }
            } else if ["pptx", "ppt"].contains(ext) {
                // PowerPoint → PDF via LibreOffice (only reliable method)
                let loPath = "/Applications/LibreOffice.app/Contents/MacOS/soffice"
                guard fm.fileExists(atPath: loPath) else {
                    return "Error: pptx needs LibreOffice. Run: brew install --cask libreoffice"
                }
                _ = try await shellExec(loPath, args: [
                    "--headless", "--convert-to", "pdf", "--outdir", settings.outputFolder, p
                ])
            } else {
                return "Error: unsupported format '\(ext)'. Supported: images, docx, doc, pptx, rtf, txt, html, md, or folder of images"
            }
            return "Saved to \(outputPath)"
        }
    ))

    // file to markdown
    registry.register(ToolCommand(
        path: ["file", "to", "markdown"],
        description: "Convert PDF/docx to markdown (drag & drop)",
        parameterName: "file",
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: drag & drop a file" }
            let p = (filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: p) else { return "Error: file not found" }
            let baseName = ((p as NSString).lastPathComponent as NSString).deletingPathExtension
            let outputPath = "\(settings.outputFolder)/\(baseName).md"
            let ext = (p as NSString).pathExtension.lowercased()

            if ext == "pdf" {
                let script = "import sys; from Quartz import PDFDocument; from Foundation import NSURL; d=PDFDocument.alloc().initWithURL_(NSURL.fileURLWithPath_(sys.argv[1])); print(''.join([d.pageAtIndex_(i).string() or '' for i in range(d.pageCount())]))"
                let text = try await shellExec(PythonEnv.shared.pythonPath, args: ["-c", script, p])
                try text.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } else if ["docx", "doc", "rtf", "html"].contains(ext) {
                // textutil can convert to HTML, then we strip to basic markdown
                let htmlPath = NSTemporaryDirectory() + "\(baseName).html"
                _ = try await shellExec("/usr/bin/textutil", args: ["-convert", "html", "-output", htmlPath, p])
                let html = try String(contentsOfFile: htmlPath, encoding: .utf8)
                // Basic HTML to markdown conversion
                var md = html
                    .replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
                    .replacingOccurrences(of: "<p[^>]*>", with: "\n\n", options: .regularExpression)
                    .replacingOccurrences(of: "</p>", with: "")
                    .replacingOccurrences(of: "<h1[^>]*>", with: "\n# ", options: .regularExpression)
                    .replacingOccurrences(of: "</h1>", with: "\n")
                    .replacingOccurrences(of: "<h2[^>]*>", with: "\n## ", options: .regularExpression)
                    .replacingOccurrences(of: "</h2>", with: "\n")
                    .replacingOccurrences(of: "<h3[^>]*>", with: "\n### ", options: .regularExpression)
                    .replacingOccurrences(of: "</h3>", with: "\n")
                    .replacingOccurrences(of: "<strong[^>]*>", with: "**", options: .regularExpression)
                    .replacingOccurrences(of: "</strong>", with: "**")
                    .replacingOccurrences(of: "<b[^>]*>", with: "**", options: .regularExpression)
                    .replacingOccurrences(of: "</b>", with: "**")
                    .replacingOccurrences(of: "<em[^>]*>", with: "_", options: .regularExpression)
                    .replacingOccurrences(of: "</em>", with: "_")
                    .replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)
                    .replacingOccurrences(of: "</li>", with: "\n")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                md = md.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
                try md.trimmingCharacters(in: .whitespacesAndNewlines).write(toFile: outputPath, atomically: true, encoding: .utf8)
                try? FileManager.default.removeItem(atPath: htmlPath)
            } else {
                return "Error: unsupported format '\(ext)'. Use PDF, docx, doc, rtf, or html."
            }
            return "Saved to \(outputPath)"
        }
    ))

    // file compress — compress an image
    registry.register(ToolCommand(
        path: ["file", "compress"],
        description: "Compress an image (drag & drop)",
        parameterName: "image",
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: drag & drop an image" }
            let p = (filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: p) else { return "Error: file not found" }
            let baseName = ((p as NSString).lastPathComponent as NSString).deletingPathExtension
            let outputPath = "\(settings.outputFolder)/\(baseName)_compressed.jpg"

            let beforeSize = (try? FileManager.default.attributesOfItem(atPath: p)[.size] as? Int64) ?? 0

            // Use sips to convert to JPEG at 80% quality
            _ = try await shellExec("/usr/bin/sips", args: [
                "-s", "format", "jpeg", "-s", "formatOptions", "80", p, "--out", outputPath
            ])

            let afterSize = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int64) ?? 0
            let ratio = beforeSize > 0 ? Int((1.0 - Double(afterSize) / Double(beforeSize)) * 100) : 0
            return "Saved to \(outputPath)\n\(formatSize(beforeSize)) → \(formatSize(afterSize)) (-\(ratio)%)"
        }
    ))



    // ============================================================
    // MARK: - FILE QA (LLM)
    // ============================================================

    registry.register(ToolCommand(
        path: ["file", "qa"],
        description: "Chat with a file (drag & drop)",
        parameterName: "file",
        usesLLM: true,
        handler: { input in
            return "__FILE_QA__:\(input)"
        }
    ))

    // ============================================================
    // MARK: - TRANSLATE
    // ============================================================

    registry.register(ToolCommand(
        path: ["translate"],
        description: "Translate word or phrase (e.g. translate poisson english)",
        parameterName: "text :lang",
        handler: { input in
            guard !input.isEmpty else { return "Error: usage: translate [text] :[lang] or translate [text] [language]" }

            // Parse target language
            let parts = input.trimmingCharacters(in: .whitespaces)
            var targetLang = settings.defaultTranslateTarget
            var textToTranslate = parts

            // Support ":en" syntax
            if let colonRange = parts.range(of: #"\s+:[a-zA-Z]{2,5}$"#, options: .regularExpression) {
                targetLang = String(parts[colonRange]).trimmingCharacters(in: .whitespaces).dropFirst().lowercased()
                textToTranslate = String(parts[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            // Support language names
            let langMap: [String: String] = [
                "english": "en", "french": "fr", "spanish": "es", "german": "de",
                "italian": "it", "portuguese": "pt", "chinese": "zh", "japanese": "ja",
                "korean": "ko", "arabic": "ar", "russian": "ru", "dutch": "nl",
                "anglais": "en", "francais": "fr", "espagnol": "es", "allemand": "de",
            ]
            let words = parts.split(separator: " ").map(String.init)
            if let lastWord = words.last?.lowercased(), let code = langMap[lastWord] {
                targetLang = code
                textToTranslate = words.dropLast().joined(separator: " ")
            }
            guard !textToTranslate.isEmpty else { return "Error: no text to translate" }

            // Check settings: CLI (Google) or LLM
            if settings.translateMode == "llm" {
                let toolPath = "translate"
                let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
                let provider = settings.getProvider(for: toolPath)
                return try await LLMService.call(provider: provider, systemPrompt: prompt,
                    userMessage: "Translate to \(targetLang): \(textToTranslate)")
            }

            // CLI mode: translate-shell (Google Translate)
            let trans = try await ensureDep("trans", brew: "translate-shell")

            // Detect source language first
            let detected = try await shellExec(trans, args: ["-id", "-no-ansi", "-b", textToTranslate])
            var sourceLang = detected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // -id returns something like "fr" or "French"
            if sourceLang.count > 3 { sourceLang = "" }

            // If detected source == target, flip to a sensible default
            if sourceLang == targetLang || sourceLang.isEmpty {
                sourceLang = targetLang == "en" ? "fr" : "en"
            }

            // Brief translation (just the result)
            let brief = try await shellExec(trans, args: [
                "-b", "-no-ansi", "-s", sourceLang, "-t", targetLang, textToTranslate
            ])
            let result = brief.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { return "Error: no translation found" }
            return result
        }
    ))

    // ============================================================
    // MARK: - REPHRASE tools
    // ============================================================

    for (context, desc) in [
        ("mail", "Rephrase text as a professional email"),
        ("msg", "Rephrase text as a casual message"),
        ("teams", "Rephrase text for Teams/Slack"),
        ("idea", "Rephrase and structure a rough idea"),
    ] {
        let toolPath = "rephrase \(context)"
        registry.register(ToolCommand(
            path: ["rephrase", context],
            description: desc,
            parameterName: "text",
            usesLLM: true,
            handler: { [toolPath] input in
                guard !input.isEmpty else { return "Error: please provide text to rephrase" }
                let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
                let provider = settings.getProvider(for: toolPath)
                return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: input)
            }
        ))
    }

    // ============================================================
    // MARK: - DEF
    // ============================================================

    registry.register(ToolCommand(
        path: ["def"],
        description: "Get the definition of a word",
        parameterName: "word",
        usesLLM: true,
        handler: { word in
            guard !word.isEmpty else { return "Error: please provide a word" }
            let toolPath = "def"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: word)
        }
    ))

    // ============================================================
    // MARK: - EXPLAIN
    // ============================================================

    registry.register(ToolCommand(
        path: ["explain"],
        description: "Get a concise explanation of a concept",
        parameterName: "concept",
        usesLLM: true,
        handler: { concept in
            guard !concept.isEmpty else { return "Error: please provide a concept" }
            let toolPath = "explain"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: concept)
        }
    ))

    // ============================================================
    // MARK: - SUMMARIZE
    // ============================================================

    // summarize txt — paste or type text directly
    registry.register(ToolCommand(
        path: ["summarize", "txt"],
        description: "Summarize pasted text",
        parameterName: "text",
        usesLLM: true,
        handler: { text in
            guard !text.isEmpty else { return "Error: paste or type the text to summarize" }
            let toolPath = "summarize txt"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    // summarize link — fetches webpage then summarizes
    registry.register(ToolCommand(
        path: ["summarize", "link"],
        description: "Summarize a webpage",
        parameterName: "url",
        usesLLM: true,
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a URL" }
            let html = try await shellExec("/usr/bin/curl", args: ["-sL", "--max-time", "15", url])
            let text = html
                .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return "Error: could not fetch content from \(url)" }
            let truncated = truncateForLLM(text)
            let toolPath = "summarize link"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: "URL: \(url)\n\nContent:\n\(truncated)")
        }
    ))

    // summarize video — fetches YouTube transcript then summarizes
    registry.register(ToolCommand(
        path: ["summarize", "video"],
        description: "Summarize a YouTube video",
        parameterName: "url",
        usesLLM: true,
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let ytdlp = try await ensureDep("yt-dlp", brew: "yt-dlp")

            // Download subtitles to temp dir
            let tmpDir = NSTemporaryDirectory() + "raccoon_\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: tmpDir) }

            _ = try? await shellExec(ytdlp, args: [
                "--write-auto-sub", "--sub-lang", "en",
                "--skip-download", "-o", "\(tmpDir)/subs", url
            ])

            // Find and read the subtitle file
            let files = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir)) ?? []
            let subFile = files.first { $0.hasSuffix(".vtt") || $0.hasSuffix(".srt") }
            guard let subFile else { return "Error: no subtitles found for this video" }

            let raw = try String(contentsOfFile: "\(tmpDir)/\(subFile)", encoding: .utf8)
            let transcript = vttToPlainText(raw)
            guard !transcript.isEmpty else { return "Error: transcript is empty" }

            let truncated = truncateForLLM(transcript)
            let toolPath = "summarize video"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: "Video: \(url)\n\nTranscript:\n\(truncated)")
        }
    ))

    // summarize file — drag & drop a file to summarize
    registry.register(ToolCommand(
        path: ["summarize", "file"],
        description: "Summarize a local file (drag & drop)",
        parameterName: "path",
        usesLLM: true,
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: drag & drop a file or provide a path" }
            let expanded = (filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                return "Error: file not found at \(expanded)"
            }
            guard let data = FileManager.default.contents(atPath: expanded) else {
                return "Error: could not read file"
            }
            // Try reading as text
            let content: String
            if let text = String(data: data, encoding: .utf8) {
                content = text
            } else {
                return "Error: file doesn't appear to be a text file"
            }
            guard !content.isEmpty else { return "Error: file is empty" }
            let truncated = truncateForLLM(content)
            let filename = (expanded as NSString).lastPathComponent
            let toolPath = "summarize file"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: "File: \(filename)\n\nContent:\n\(truncated)")
        }
    ))

    // ============================================================
    // MARK: - WIFI
    // ============================================================

    registry.register(ToolCommand(
        path: ["wifi"],
        description: "Show current WiFi name and password",
        parameterName: nil,
        handler: { _ in
            // Get current WiFi SSID
            let ssidResult = try await shellExec("/usr/sbin/networksetup", args: ["-getairportnetwork", "en0"])
            let ssidLine = ssidResult.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIdx = ssidLine.range(of: ": ") else {
                return "Error: not connected to WiFi"
            }
            let ssid = String(ssidLine[colonIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ssid.isEmpty && !ssid.contains("not associated") else {
                return "Error: not connected to WiFi"
            }

            // Get password (will trigger macOS auth prompt)
            let passResult = try? await shellExec("/usr/bin/security", args: [
                "find-generic-password", "-wa", ssid, "-D", "AirPort network password"
            ])
            let password = passResult?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(access denied)"

            return "Network: \(ssid)\nPassword: \(password)"
        }
    ))

    // ============================================================
    // MARK: - COLOR PICKER
    // ============================================================

    registry.register(ToolCommand(
        path: ["color"],
        description: "Pick colors + auto palette generator",
        parameterName: nil,
        usesLLM: true,
        handler: { _ in "__COLOR_PICKER__" }
    ))

    // ============================================================
    // MARK: - SYNONYM
    // ============================================================

    registry.register(ToolCommand(
        path: ["synonym"],
        description: "List synonyms with definitions",
        parameterName: "word",
        usesLLM: true,
        handler: { input in
            guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return "Error: provide a word" }
            let prompt = settings.getSystemPrompt(for: "synonym", default: "List 5-8 synonyms for the given word. Return ONLY a JSON array, no other text. Format: [{\"word\":\"...\",\"def\":\"...\"}] where def is a brief definition with usage nuance.")
            let provider = settings.getProvider(for: "synonym")
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: input)
        }
    ))

    // ============================================================
    // MARK: - WORD (reverse dictionary)
    // ============================================================

    registry.register(ToolCommand(
        path: ["word"],
        description: "Find words that match a description",
        parameterName: "description",
        usesLLM: true,
        handler: { input in
            guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return "Error: describe what you're looking for" }
            let prompt = settings.getSystemPrompt(for: "word", default: "You are a reverse dictionary. The user describes something and you find the exact words for it. Return ONLY a JSON array, no other text. Format: [{\"word\":\"...\",\"def\":\"...\"}] with 5-8 precise, specific words. Prioritize uncommon words. Include language origin in def if interesting.")
            let provider = settings.getProvider(for: "word")
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: input)
        }
    ))

    // ============================================================
    // MARK: - FIX GRAMMAR
    // ============================================================

    registry.register(ToolCommand(
        path: ["fix", "grammar"],
        description: "Fix grammar and spelling in text or clipboard",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            // If no input, use clipboard
            if text.isEmpty {
                text = NSPasteboard.general.string(forType: .string) ?? ""
            }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            let toolPath = "fix grammar"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    registry.register(ToolCommand(
        path: ["fix", "orth"],
        description: "Fix spelling/typos in text or clipboard",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            let prompt = settings.getSystemPrompt(for: "fix orth", default: "Fix only spelling and typos in the following text. Do NOT change grammar, punctuation, or style. Return only the corrected text, no explanations.")
            let provider = settings.getProvider(for: "fix orth")
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    // fix code — fix bugs/errors in code from clipboard or input
    registry.register(ToolCommand(
        path: ["fix", "code"],
        description: "Fix bugs and errors in code (text or clipboard)",
        parameterName: "code",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no code provided and clipboard is empty" }
            let prompt = settings.getSystemPrompt(for: "fix code", default: "Fix the bugs, errors, and issues in the following code. Return ONLY the corrected code, no explanations, no markdown code fences. Preserve the original language and style.")
            let provider = settings.getProvider(for: "fix code")
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    // ============================================================
    // MARK: - CHAT
    // ============================================================

    registry.register(ToolCommand(
        path: ["chat"],
        description: "Free chat with LLM",
        parameterName: nil,
        usesLLM: true,
        handler: { _ in "__CHAT__" }
    ))

    // ============================================================
    // MARK: - PROMPT (two-step: content + instructions)
    // ============================================================

    registry.register(ToolCommand(
        path: ["prompt"],
        description: "Give content + instructions, LLM refines via Q&A",
        parameterName: nil,
        usesLLM: true,
        handler: { _ in "__PROMPT__" }
    ))

    // ============================================================
    // MARK: - REPHRASE FORMAL / CASUAL
    // ============================================================

    registry.register(ToolCommand(
        path: ["rephrase", "formal"],
        description: "Rephrase text in a formal tone",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            let toolPath = "rephrase formal"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    registry.register(ToolCommand(
        path: ["rephrase", "casual"],
        description: "Rephrase text in a casual tone",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            let toolPath = "rephrase casual"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    // ============================================================
    // MARK: - SUBJECT
    // ============================================================

    registry.register(ToolCommand(
        path: ["subject"],
        description: "Generate email subject line from text or clipboard",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            let toolPath = "subject"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    // ============================================================
    // MARK: - GOOGLE
    // ============================================================

    registry.register(ToolCommand(
        path: ["google"],
        description: "Search Google for text or clipboard",
        parameterName: "query",
        handler: { input in
            var query = input.trimmingCharacters(in: .whitespaces)
            if query.isEmpty { query = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !query.isEmpty else { return "Error: no query provided and clipboard is empty" }
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let url = "https://www.google.com/search?q=\(encoded)"
            NSWorkspace.shared.open(URL(string: url)!)
            return "Opened Google search for: \(query)"
        }
    ))

    // ============================================================
    // MARK: - MEET
    // ============================================================

    registry.register(ToolCommand(
        path: ["meet"],
        description: "Create a new Google Meet link",
        parameterName: nil,
        handler: { _ in
            let url = "https://meet.google.com/new"
            NSWorkspace.shared.open(URL(string: url)!)
            return "Opening Google Meet — the link will be in your browser URL bar"
        }
    ))

    // ============================================================
    // MARK: - HISTORY
    // ============================================================

    registry.register(ToolCommand(
        path: ["history"],
        description: "Browse clipboard history",
        parameterName: nil,
        handler: { _ in "__HISTORY__" }
    ))
}

// MARK: - LLM input truncation

// Cap content sent to the LLM (~25-30k tokens, safe for all supported models)
// and append an explicit marker when truncation actually happens.
func truncateForLLM(_ text: String, limit: Int = 100_000) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit)) + "\n\n[content truncated]"
}

// MARK: - VTT to plain text converter

func vttToPlainText(_ vtt: String) -> String {
    var lines: [String] = []
    var lastLine = ""
    for line in vtt.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Skip VTT headers, timestamps, and empty lines
        if trimmed.isEmpty || trimmed.hasPrefix("WEBVTT") || trimmed.hasPrefix("Kind:")
            || trimmed.hasPrefix("Language:") || trimmed.contains("-->")
            || trimmed.allSatisfy({ $0.isNumber || $0 == ":" || $0 == "." || $0 == " " }) {
            continue
        }
        // Remove HTML tags from subtitle text
        let clean = trimmed.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if clean != lastLine && !clean.isEmpty {
            lines.append(clean)
            lastLine = clean
        }
    }
    return lines.joined(separator: "\n")
}

// MARK: - Dependency management

func ensureDep(_ name: String, brew: String? = nil) async throws -> String {
    let paths = [
        "/opt/homebrew/bin/\(name)",
        "/usr/local/bin/\(name)",
        "/usr/bin/\(name)",
    ]
    for path in paths {
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    if let result = try? await shellExec("/bin/zsh", args: ["-lc", "which \(name)"]) {
        let found = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !found.isEmpty && found.contains("/") && !found.contains("not found") {
            return found
        }
    }
    if let brew {
        let brewPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
            ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew"
        if FileManager.default.fileExists(atPath: brewPath) {
            _ = try await shellExec(brewPath, args: ["install", brew])
            for path in paths {
                if FileManager.default.fileExists(atPath: path) { return path }
            }
        }
    }
    throw ToolError.dependencyMissing(name)
}

enum ToolError: LocalizedError {
    case dependencyMissing(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .dependencyMissing(let name):
            return "\(name) not found. Run: brew install \(name)"
        case .cancelled:
            return "Cancelled"
        }
    }
}

// MARK: - Shell execution

func formatSize(_ bytes: Int64) -> String {
    if bytes > 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
    if bytes > 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1e6) }
    if bytes > 1_000 { return String(format: "%.1f KB", Double(bytes) / 1e3) }
    return "\(bytes) B"
}

func shellExec(_ command: String, args: [String], taskID: UUID? = nil) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
            if let taskID { ProcessManager.shared.register(taskID, process: process) }

            // Ensure brew + venv are in PATH
            var env = ProcessInfo.processInfo.environment
            let brewPaths = "/opt/homebrew/bin:/usr/local/bin"
            let venvBin = PythonEnv.shared.venvDir + "/bin"
            env["PATH"] = "\(venvBin):\(brewPaths):\(env["PATH"] ?? "/usr/bin:/bin")"
            process.environment = env

            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()
                if let taskID { ProcessManager.shared.processes.removeValue(forKey: taskID) }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let errOutput = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output.isEmpty ? "Done" : output)
                } else if process.terminationStatus == 15 {
                    continuation.resume(throwing: ToolError.cancelled)
                } else {
                    let msg = errOutput.isEmpty ? output : errOutput
                    continuation.resume(returning: "Error (exit \(process.terminationStatus)): \(msg)")
                }
            } catch {
                if let taskID { ProcessManager.shared.processes.removeValue(forKey: taskID) }
                continuation.resume(throwing: error)
            }
        }
    }
}
