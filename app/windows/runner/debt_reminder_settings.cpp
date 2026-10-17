#include <windows.h>
#include <shellapi.h>
#include <roapi.h>
#include <windows.ui.notifications.h>
#include <wrl.h>
#include <wrl/wrappers/corewrappers.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include "debt_reminder_settings.h"

// Query the actual notifier setting for the same AUMID used by the OS adapter.
// No permissions or registry settings are changed here.
void RegisterDebtReminderSettings(flutter::BinaryMessenger* messenger) {
  flutter::MethodChannel<flutter::EncodableValue> channel(
      messenger, "eldafttar/debt_reminders", &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "settings") {
      const auto opened = reinterpret_cast<INT_PTR>(ShellExecuteW(
          nullptr, L"open", L"ms-settings:notifications", nullptr, nullptr, SW_SHOWNORMAL));
      result->Success(flutter::EncodableValue(opened > 32));
      return;
    }
    if (call.method_name() != "enabled") { result->NotImplemented(); return; }
    using namespace ABI::Windows::UI::Notifications;
    Microsoft::WRL::ComPtr<IToastNotificationManagerStatics> manager;
    HRESULT hr = RoGetActivationFactory(
        Microsoft::WRL::Wrappers::HStringReference(RuntimeClass_Windows_UI_Notifications_ToastNotificationManager).Get(),
        IID_PPV_ARGS(&manager));
    Microsoft::WRL::ComPtr<IToastNotifier> notifier;
    if (SUCCEEDED(hr)) hr = manager->CreateToastNotifierWithId(
        Microsoft::WRL::Wrappers::HStringReference(L"ElDafttar.ERP.DebtReminders").Get(), &notifier);
    NotificationSetting setting = NotificationSetting_DisabledByManifest;
    if (SUCCEEDED(hr)) hr = notifier->get_Setting(&setting);
    if (FAILED(hr)) { result->Error("notification_setup", "Windows notification setup unavailable"); return; }
    result->Success(flutter::EncodableValue(setting == NotificationSetting_Enabled));
  });
}
