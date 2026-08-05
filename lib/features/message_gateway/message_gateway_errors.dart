import '../../shared/util/user_failure_message.dart';

String messageGatewayFailureMessage(Object error, {required String fallback}) {
  return userFailureMessage(error, fallback: fallback);
}
