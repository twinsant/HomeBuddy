//
//  SetupNotice.swift
//  HomeBuddy
//
//  首次启动提示：只说明缺什么，不阻断浏览。
//

import SwiftUI

struct SetupNotice: View {
    let needsPhotoAccess: Bool
    let needsFaceModel: Bool
    let openPhotoSettings: () -> Void

    var body: some View {
        if needsPhotoAccess || needsFaceModel {
            VStack(alignment: .leading, spacing: 8) {
                if needsPhotoAccess {
                    row(
                        icon: "photo.slash",
                        title: "还没允许访问照片图库",
                        detail: "允许之后，系统相册会出现在左侧。也可以先用「添加目录…」浏览磁盘上的照片文件夹。",
                        action: AnyView(
                            Button("打开照片设置", action: openPhotoSettings)
                                .controlSize(.small)
                        )
                    )
                }
                if needsFaceModel {
                    row(
                        icon: "person.crop.square.badge.camera",
                        title: "人脸识别还没有模型",
                        detail: "浏览、相册、元数据和文件夹都不需要模型。要认人，先在设置里选一个 antelopev2.gguf 兼容的模型文件。",
                        action: AnyView(
                            SettingsLink { Text("打开设置") }
                                .controlSize(.small)
                        )
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
        }
    }

    private func row(icon: String, title: String, detail: String, action: AnyView) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action
        }
    }
}

#Preview {
    SetupNotice(needsPhotoAccess: true, needsFaceModel: true, openPhotoSettings: {})
        .frame(width: 720)
}
