import Foundation

// MARK: - whisper-cpp progress parsing (pure, unit-testable)

/// Parses a whisper-cpp `--print-progress` line like
/// "whisper_print_progress_callback: progress =  15%" into a 0–1 fraction.
/// Returns nil for any other line (behavior stays indeterminate if whisper
/// never prints progress).
@Sendable func parseWhisperProgress(_ line: String) -> Double? {
    guard line.contains("progress") else { return nil }
    guard let range = line.range(of: #"progress\s*=\s*\d+(\.\d+)?%"#, options: .regularExpression) else { return nil }
    let match = line[range]
    guard let pctRange = match.range(of: #"\d+(\.\d+)?"#, options: .regularExpression),
          let pct = Double(match[pctRange]) else { return nil }
    return min(max(pct / 100, 0), 1)
}

func registerFileTools(registry: ToolRegistry, settings: SettingsManager) {
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
                _ = try await shellExec("/usr/bin/curl", args: ["-fL", "-o", modelPath, modelURL])
                // A failed download can leave a partial/empty file that would
                // be treated as a valid model forever — verify and clean up
                let attrs = try? FileManager.default.attributesOfItem(atPath: modelPath)
                let size = (attrs?[.size] as? Int64) ?? 0
                if size < 10_000_000 {
                    try? FileManager.default.removeItem(atPath: modelPath)
                    return "Error: Whisper model download failed (incomplete file). Check your network connection and try again."
                }
            }

            let baseName = (expandedPath as NSString).lastPathComponent
                .replacingOccurrences(of: ".", with: "_")
            let taskID = await runningTaskID(for: "get file transcript")
            let result = try await shellExec(whisper, args: [
                "-m", modelPath, "-f", expandedPath,
                "-otxt", "--print-progress", "-of", "\(output)/\(baseName)"
            ], taskID: taskID, onLine: progressLineHandler(taskID: taskID, parser: parseWhisperProgress))
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
}

func formatSize(_ bytes: Int64) -> String {
    if bytes > 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
    if bytes > 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1e6) }
    if bytes > 1_000 { return String(format: "%.1f KB", Double(bytes) / 1e3) }
    return "\(bytes) B"
}
