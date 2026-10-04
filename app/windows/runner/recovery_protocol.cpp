#include "recovery_protocol.h"

#include <windows.h>

#include <string>

namespace {

bool SetStringValue(HKEY key, const wchar_t* name, const wchar_t* value) {
  const auto bytes =
      static_cast<DWORD>((wcslen(value) + 1) * sizeof(wchar_t));
  return RegSetValueExW(
             key,
             name,
             0,
             REG_SZ,
             reinterpret_cast<const BYTE*>(value),
             bytes) == ERROR_SUCCESS;
}

}  // namespace

void RegisterEldafttarRecoveryProtocol() {
  wchar_t executable[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, executable, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return;
  }

  HKEY scheme_key = nullptr;
  if (::RegCreateKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Classes\\eldafttar",
          0,
          nullptr,
          0,
          KEY_SET_VALUE,
          nullptr,
          &scheme_key,
          nullptr) != ERROR_SUCCESS) {
    return;
  }
  SetStringValue(scheme_key, nullptr, L"URL:Eldafttar");
  SetStringValue(scheme_key, L"URL Protocol", L"");
  ::RegCloseKey(scheme_key);

  HKEY command_key = nullptr;
  if (::RegCreateKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Classes\\eldafttar\\shell\\open\\command",
          0,
          nullptr,
          0,
          KEY_SET_VALUE,
          nullptr,
          &command_key,
          nullptr) != ERROR_SUCCESS) {
    return;
  }
  std::wstring command = L"\"";
  command += executable;
  command += L"\" \"%1\"";
  SetStringValue(command_key, nullptr, command.c_str());
  ::RegCloseKey(command_key);
}
