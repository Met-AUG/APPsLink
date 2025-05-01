//
//  ContentView.swift
//  APPsLink
//
//  Created by 李秉璋 on 2025/5/1.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var showingDirectoryPicker = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 20)
    ]
    
    var body: some View {
        VStack {
            if viewModel.selectedDirectory == nil {
                VStack(spacing: 20) {
                    Image(systemName: "folder.badge.plus")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundColor(.blue)
                    
                    Text("请选择一个包含应用程序的文件夹")
                        .font(.headline)
                    
                    Button("选择文件夹") {
                        showingDirectoryPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    
                    // 添加获取权限按钮
                    Button("获取管理员权限") {
                        viewModel.requestAdminPermission { success in
                            if success {
                                alertMessage = "已成功获取管理员权限，现在可以创建软链接了"
                            } else {
                                alertMessage = "获取管理员权限失败，可能无法创建软链接"
                            }
                            showingAlert = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                VStack {
                    // 顶部工具栏区域
                    HStack {
                        Text("当前目录: \(viewModel.selectedDirectory?.path ?? "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Button(action: {
                            if let directory = viewModel.selectedDirectory {
                                viewModel.scanDirectory(directory)
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                        }
                        .disabled(viewModel.isScanning)
                        .help("刷新")
                        
                        Button("更改") {
                            showingDirectoryPicker = true
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    
                    // 获取权限按钮状态
                    HStack {
                        Label(
                            viewModel.hasPermission ? "已获取管理员权限" : "尚未获取管理员权限",
                            systemImage: viewModel.hasPermission ? "checkmark.shield" : "shield"
                        )
                        .font(.caption)
                        .foregroundColor(viewModel.hasPermission ? .green : .orange)
                        
                        Spacer()
                        
                        if !viewModel.hasPermission {
                            Button("获取权限") {
                                viewModel.requestAdminPermission { success in
                                    if success {
                                        alertMessage = "已成功获取管理员权限，现在可以创建软链接了"
                                    } else {
                                        alertMessage = "获取管理员权限失败，可能无法创建软链接"
                                    }
                                    showingAlert = true
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.blue)
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    
                    // 分割线
                    Divider()
                        .padding(.horizontal)
                    
                    // 显示应用列表
                    if viewModel.isScanning {
                        ProgressView("正在扫描应用...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.apps.isEmpty {
                        VStack {
                            Image(systemName: "app.slash")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 60, height: 60)
                                .foregroundColor(.gray)
                            
                            Text("未找到应用程序")
                                .font(.headline)
                                .padding(.top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(viewModel.apps) { app in
                                    AppItemView(app: app, hasPermission: viewModel.hasPermission) {
                                        if !app.isLinked && viewModel.hasPermission {
                                            let destination = "/Applications/\(app.url.lastPathComponent)"
                                            if viewModel.createSymbolicLinkWithAdmin(from: app.url, to: destination) {
                                                // 刷新状态
                                                viewModel.refreshLinkStatus()
                                                alertMessage = "已成功创建 \(app.name) 的软链接"
                                                showingAlert = true
                                            } else {
                                                alertMessage = "无法创建 \(app.name) 的软链接，请检查权限"
                                                showingAlert = true
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        
                        // 一键创建所有软链接的按钮
                        Button("为所有未链接的应用创建软链接") {
                            let count = viewModel.createAllLinksWithAdmin()
                            if count > 0 {
                                alertMessage = "已成功创建 \(count) 个应用的软链接"
                            } else {
                                alertMessage = "没有需要创建软链接的应用"
                            }
                            showingAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom)
                        .disabled(!viewModel.hasPermission || viewModel.apps.filter { !$0.isLinked }.isEmpty)
                    }
                }
            }
        }
        .navigationTitle("APPsLink")
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // 开始访问安全区域外的URL
                    let didStartAccessing = url.startAccessingSecurityScopedResource()
                    
                    // 扫描目录
                    viewModel.scanDirectory(url)
                    
                    // 如果不需要长期访问，可以在这里停止
                    // 但我们的模型会保存书签并在需要时管理访问
                    if !didStartAccessing {
                        print("警告：无法访问安全区域资源")
                    }
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("提示"), message: Text(alertMessage), dismissButton: .default(Text("确定")))
        }
        .alert(item: Binding<AppError?>(
            get: { viewModel.errorMessage != nil ? AppError(message: viewModel.errorMessage!) : nil },
            set: { newValue in viewModel.errorMessage = newValue?.message }
        )) { error in
            Alert(title: Text("错误"), message: Text(error.message), dismissButton: .default(Text("确定")))
        }
    }
}

struct AppItemView: View {
    let app: AppItem
    let hasPermission: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .overlay(
                    app.isLinked ? AnyView(
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 20))
                            .background(Circle().fill(Color.white))
                            .offset(x: 25, y: 25)
                    ) : AnyView(EmptyView())
                )
            
            Text(app.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 40)
            
            if !app.isLinked {
                Button("创建链接") {
                    onTap()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
                .font(.caption)
                .disabled(!hasPermission)
            } else {
                Text("已链接")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .frame(width: 120, height: 150)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.textBackgroundColor))
                .shadow(radius: 2)
        )
        .onTapGesture {
            if !app.isLinked && hasPermission {
                onTap()
            }
        }
    }
}

struct AppError: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    ContentView()
}
