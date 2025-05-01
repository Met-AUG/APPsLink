import Foundation
import AppKit

class AppItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let icon: NSImage
    var isLinked: Bool
    
    init(url: URL) {
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        
        // 获取应用图标
        let bundleIcon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon = bundleIcon
        
        // 检查是否已经创建了软链接
        let linkedPath = "/Applications/\(url.lastPathComponent)"
        isLinked = FileManager.default.fileExists(atPath: linkedPath)
    }
    
    func createSymbolicLink() -> Bool {
        let destination = "/Applications/\(url.lastPathComponent)"
        
        do {
            // 如果已经存在，先删除
            try? FileManager.default.removeItem(atPath: destination)
            
            try FileManager.default.createSymbolicLink(at: URL(fileURLWithPath: destination), 
                                                     withDestinationURL: url)
            return true
        } catch {
            print("创建软链接失败: \(error)")
            return false
        }
    }
}

class AppViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var selectedDirectory: URL?
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var hasPermission = false
    
    // 存储书签数据的用户默认值键
    private let bookmarkKey = "selectedDirectoryBookmark"
    
    // 创建一个脚本文件，用于批量创建软链接
    private var batchScriptPath: String?
    
    init() {
        restoreSavedDirectory()
    }
    
    private func restoreSavedDirectory() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return
        }
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                // 书签已过期，需要重新创建
                print("书签已过期")
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                return
            }
            
            // 开始访问安全区域外的URL
            if url.startAccessingSecurityScopedResource() {
                self.selectedDirectory = url
                scanDirectory(url)
            }
        } catch {
            print("恢复目录失败: \(error)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }
    
    func saveDirectoryBookmark(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        } catch {
            print("保存目录书签失败: \(error)")
        }
    }
    
    func scanDirectory(_ url: URL) {
        isScanning = true
        errorMessage = nil
        apps = []
        
        // 确保只有一个目录被访问
        if let oldURL = selectedDirectory, oldURL != url {
            oldURL.stopAccessingSecurityScopedResource()
        }
        
        // 保存新选择的目录的书签
        saveDirectoryBookmark(url)
        
        DispatchQueue.global().async {
            do {
                let fileManager = FileManager.default
                let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                
                // 筛选出.app文件
                let appFiles = contents.filter { $0.pathExtension == "app" }
                
                // 创建AppItem对象
                let appItems = appFiles.map { AppItem(url: $0) }
                
                DispatchQueue.main.async {
                    self.apps = appItems
                    self.selectedDirectory = url
                    self.isScanning = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "扫描目录失败: \(error.localizedDescription)"
                    self.isScanning = false
                }
            }
        }
    }
    
    func createAllLinks() -> Int {
        var successCount = 0
        
        for i in 0..<apps.count {
            if !apps[i].isLinked {
                if apps[i].createSymbolicLink() {
                    apps[i].isLinked = true
                    successCount += 1
                }
            }
        }
        
        return successCount
    }
    
    func refreshLinkStatus() {
        for i in 0..<apps.count {
            let linkedPath = "/Applications/\(apps[i].url.lastPathComponent)"
            apps[i].isLinked = FileManager.default.fileExists(atPath: linkedPath)
        }
    }
    
    // 获取管理员权限的方法
    func requestAdminPermission(completion: @escaping (Bool) -> Void) {
        // 创建一个简单的脚本来验证和保持权限
        let script = """
        do shell script "echo 'Administrator authentication successful'" with administrator privileges
        """
        
        // 执行脚本获取管理员权限
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                self.hasPermission = true
                
                // 另外创建辅助脚本，用于后续操作
                let tmpDir = FileManager.default.temporaryDirectory
                let scriptURL = tmpDir.appendingPathComponent("appslink_helper.sh")
                batchScriptPath = scriptURL.path
                
                let helperScript = """
                #!/bin/bash
                # 这个脚本用于创建软链接
                
                # 创建指定的软链接
                if [ $# -eq 2 ]; then
                    ln -sf "$1" "$2"
                    exit $?
                fi
                
                # 没有参数时输出帮助
                echo "Usage: $0 source_path target_path"
                exit 1
                """
                
                try helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
                
                completion(true)
            } else {
                self.hasPermission = false
                completion(false)
            }
        } catch {
            print("权限验证失败: \(error)")
            self.hasPermission = false
            completion(false)
        }
    }
    
    // 使用管理员权限创建单个软链接
    func createSymbolicLinkWithAdmin(from sourceURL: URL, to destinationPath: String) -> Bool {
        guard hasPermission else {
            print("尚未获取管理员权限")
            return false
        }
        
        let script = """
        do shell script "ln -sf '\(sourceURL.path)' '\(destinationPath)'"
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let errorOutput = String(data: data, encoding: .utf8) {
                    print("创建链接失败: \(errorOutput)")
                }
                return false
            }
            
            return FileManager.default.fileExists(atPath: destinationPath)
        } catch {
            print("执行脚本失败: \(error)")
            return false
        }
    }
    
    // 一次创建所有软链接（使用管理员权限）
    func createAllLinksWithAdmin() -> Int {
        guard hasPermission else {
            print("尚未获取管理员权限")
            return 0
        }
        
        var successCount = 0
        var scriptCommands = ""
        
        for app in apps where !app.isLinked {
            let destination = "/Applications/\(app.url.lastPathComponent)"
            scriptCommands += "ln -sf '\(app.url.path)' '\(destination)'\n"
        }
        
        if scriptCommands.isEmpty {
            return 0
        }
        
        let script = """
        do shell script "\(scriptCommands)"
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let errorOutput = String(data: data, encoding: .utf8) {
                    print("批量创建链接失败: \(errorOutput)")
                }
                return 0
            }
            
            // 更新链接状态
            for i in 0..<apps.count {
                if !apps[i].isLinked {
                    let destination = "/Applications/\(apps[i].url.lastPathComponent)"
                    if FileManager.default.fileExists(atPath: destination) {
                        apps[i].isLinked = true
                        successCount += 1
                    }
                }
            }
            
            return successCount
        } catch {
            print("批量创建链接失败: \(error)")
            return 0
        }
    }
    
    // 析构函数，确保停止访问安全区域
    deinit {
        selectedDirectory?.stopAccessingSecurityScopedResource()
    }
}