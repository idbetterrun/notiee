import SwiftUI

struct PrivacyAgreementView: View {
    @Binding var hasAgreed: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding(.top, 40)
            
            Text("欢迎使用 Notiee")
                .font(.largeTitle.weight(.bold))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("在您使用 Notiee 之前，我们需要向您说明基本情况：")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• 基本类型：个人效率与记录工具")
                        Text("• 基本业务功能：提供拍照记录、文字记录、语音记录及 AI 智能整理归纳功能。")
                        Text("• 个人信息收集范围：为实现上述功能，我们会请求您的相机、相册、麦克风及语音识别权限。应用产生的所有本地数据原则上均保存在您的设备或您的私人 iCloud 空间中。当您使用 AI 功能时，相关的文本及图片数据将会加密发送至您所选定的 AI 服务商接口进行处理，Notiee 本身不会在云端收集、截留或存储您的这些内容数据。")
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                    
                    Text("请阅读完整的")
                        .font(.callout)
                    +
                    Text("《用户协议》")
                        .foregroundColor(.blue)
                        .font(.callout)
                    +
                    Text("及")
                        .font(.callout)
                    +
                    Text("《隐私政策》")
                        .foregroundColor(.blue)
                        .font(.callout)
                    
                    Text("点击“同意”即表示您已阅读并同意上述协议。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            VStack(spacing: 16) {
                Button {
                    hasAgreed = true
                } label: {
                    Text("同意并继续")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button {
                    exit(0)
                } label: {
                    Text("不同意并退出")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}
