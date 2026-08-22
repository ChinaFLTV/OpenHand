// 设置功能由组件组成，不单独提供控制器，使用全局 SettingsController。
// 仅导出入口组件和顶层弹窗辅助方法。
export 'widgets/settings_view.dart'
    show AiUsageAnalyticsView, SettingsView, showAiModelEditorDialog;
export 'widgets/thread_session_management_dialog.dart'
    show showThreadSessionManagementDialog;
