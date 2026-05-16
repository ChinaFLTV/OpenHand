// Controller / module
export 'ai_module.dart';
export 'ai_session_controller.dart';

// Domain models (sibling features use these by name)
export 'model/ai_attachment.dart';
export 'model/ai_creation_mode.dart';
export 'model/ai_model_catalog.dart';
export 'model/ai_model_config.dart';
export 'model/ai_session.dart';
export 'model/ai_session_message.dart';
export 'model/ai_session_runtime_context.dart';
export 'model/ai_thread_template.dart';
export 'model/ai_token_usage.dart';

// Services consumed by siblings (mcp / message_gateway / home / hardness)
export 'service/ai_bash_tool_service.dart'
    show BashCommandApprovalDecision, BashCommandApprovalRequest;
export 'service/ai_chat_service.dart';
export 'service/ai_claude_hook_service.dart';
export 'service/ai_image_generation_service.dart';
export 'service/ai_protocol_adapter.dart';
export 'service/ai_tool_execution_registry.dart';
export 'service/ai_tool_runtime_service.dart';
export 'service/ai_transport_diagnostic_messages.dart';
export 'service/lsp_client_service.dart';
export 'service/mcp_loaded_tools_tracker.dart';
export 'service/self_learning_dispatcher.dart';
export 'service/self_learning_runner.dart';
export 'service/self_learning_scheduler.dart';
export 'service/web_fetch/web_fetch_cache_store.dart';
export 'service/web_search/web_search_cache_store.dart';

// Tool plumbing (some sibling features peek at registry types)
export 'tools/ai_tool.dart';

// Data layer (controller persistence — exported for jsonl exporter access)
export 'data/ai_session_store.dart';
