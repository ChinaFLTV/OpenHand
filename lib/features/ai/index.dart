// AI 功能对外接口。内部实现仅在存在跨功能依赖时导出。

export 'ai_module.dart';
export 'ai_session_controller.dart';

// 数据
export 'data/ai_session_store.dart';
export 'data/openrouter_model_profile_store.dart';

// 模型
export 'model/ai_allow_command_rule.dart';
export 'model/ai_api_dialect.dart';
export 'model/ai_api_family.dart';
export 'model/ai_attachment.dart';
export 'model/ai_auto_title_fetch_mode.dart';
export 'model/ai_builtin_tool_config.dart';
export 'model/ai_command_rule.dart';
export 'model/ai_context_usage.dart';
export 'model/ai_cost_breakdown.dart';
export 'model/ai_creation_mode.dart';
export 'model/ai_deny_command_rule.dart';
export 'model/ai_dingtalk_dws_command.dart';
export 'model/ai_endpoint_override.dart';
export 'model/ai_input_cache_policy.dart';
export 'model/ai_lsp_backend_catalog.dart';
export 'model/ai_lsp_language_settings.dart';
export 'model/ai_message_content_format.dart';
export 'model/ai_model_catalog.dart';
export 'model/ai_model_config.dart';
export 'model/ai_one_million_context_policy.dart';
export 'model/ai_operation_routing.dart';
export 'model/ai_realtime_config.dart';
export 'model/ai_sandbox_settings.dart';
export 'model/ai_session.dart';
export 'model/ai_session_goal.dart';
export 'model/ai_session_message.dart';
export 'model/ai_session_runtime_context.dart';
export 'model/ai_stream_throttle_override.dart';
export 'model/ai_thread_template.dart';
export 'model/ai_token_usage.dart';
export 'model/ai_translation_provider_catalog.dart';
export 'model/ai_translation_settings.dart';
export 'model/ai_tts_provider_catalog.dart';
export 'model/ai_tts_settings.dart';
export 'model/ai_usage_analytics.dart';
export 'model/ai_web_engine_resilience.dart';
export 'model/ai_web_fetch_settings.dart';
export 'model/ai_web_search_settings.dart';
export 'model/offline_speech_model.dart';

// 服务
export 'service/bash/ai_bash_tool_service.dart';
export 'service/chat/ai_chat_service.dart';
export 'service/chat/ai_protocol_adapter.dart';
export 'service/chat/ai_transport_diagnostic_messages.dart';
export 'service/fs/ai_attachment_input_capabilities.dart';
export 'service/fs/ai_file_history_service.dart';
export 'service/fs/ai_file_mutation_ledger.dart';
export 'service/git/ai_git_snapshot_service.dart';
export 'service/hook/ai_claude_hook_service.dart';
export 'service/lsp/ai_lsp_managed_install_service.dart';
export 'service/lsp/lsp_client_service.dart';
export 'service/mcp_bridge/mcp_loaded_tools_tracker.dart';
export 'service/media/ai_image_generation_service.dart';
export 'service/media/media_cache_service.dart';
export 'service/model_registry/ai_model_scanner.dart';
export 'service/model_registry/ai_session_model_resolver.dart';
export 'service/model_registry/ai_title_model_resolver.dart';
export 'service/model_registry/openrouter_model_sync_service.dart';
export 'service/operations/ai_embeddings_service.dart';
export 'service/operations/ai_minimax_voice_service.dart';
export 'service/operations/ai_operation_http.dart';
export 'service/operations/ai_rerank_service.dart';
export 'service/operations/ai_speech_text_polishing_service.dart';
export 'service/operations/ai_translation_service.dart';
export 'service/operations/ai_tts_playback_service.dart';
export 'service/operations/ai_voice_conversation_service.dart';
export 'service/operations/offline_speech_model_service.dart';
export 'service/prompt/ai_output_format_prompts.dart';
export 'service/prompt/ai_prompt_builder.dart';
export 'service/prompt/ai_prompt_template_assembly.dart';
export 'service/prompt/ai_prompt_template_repository.dart';
export 'service/runtime/ai_builtin_tool_lazy_loading_applier.dart';
export 'service/runtime/ai_endpoint_router.dart';
export 'service/runtime/ai_session_runtime_context_builder.dart';
export 'service/runtime/ai_tool_execution_registry.dart';
export 'service/runtime/ai_tool_runtime_service.dart';
export 'service/runtime/ai_resource_usage_payload.dart';
export 'service/runtime/ai_tool_usage_promotion_store.dart';
export 'service/sandbox/ai_sandbox_service.dart';
export 'service/self_learning/self_learning_dispatcher.dart';
export 'service/self_learning/self_learning_runner.dart';
export 'service/self_learning/self_learning_scheduler.dart';
export 'service/session_io/ai_session_jsonl_exporter.dart';
export 'service/session_io/ai_token_usage_parser.dart';
export 'service/usage/ai_usage_tracker.dart';
export 'service/web_engine/web_engine_base.dart';
export 'service/web_engine/web_engine_cache_store_base.dart'
    show WebEngineCacheStoreBase;
export 'service/web_engine/web_engine_telemetry_store_base.dart';
export 'service/web_fetch/web_fetch_cache_store.dart';
export 'service/web_fetch/web_fetch_scrapling_bridge.dart';
export 'service/web_fetch/web_fetch_telemetry_store.dart';
export 'service/web_reverse_runtime_metadata.dart';
export 'service/web_search/web_search_cache_store.dart';
export 'service/web_search/web_search_telemetry_store.dart';
export 'service/workspace/ai_workspace_instruction_service.dart';

// 工具
export 'tools/ai_tool_execution_context.dart';
export 'tools/android_reverse_adb_command_guard.dart';
export 'tools/dingtalk/ai_dingtalk_dws_tool.dart';
export 'tools/dingtalk/ai_dingtalk_media_generation_tool.dart';
export 'tools/planning/ai_ask_user_choice_tool.dart';
export 'tools/search/ai_dingtalk_tool_search_tool.dart';
export 'tools/search/ai_tool_search_tool.dart';
export 'tools/workflow/ai_workflow_tools.dart';

// 工具函数
export 'widgets/resource_usage_statistics_dialog.dart'
    show
        resourceUsageKindLabel,
        resourceUsageStatisticsButton,
        resourceUsageStatisticsLabel,
        showResourceUsageStatisticsDialog;
