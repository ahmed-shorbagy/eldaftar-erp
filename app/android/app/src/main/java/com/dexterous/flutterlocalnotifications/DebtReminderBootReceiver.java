package com.dexterous.flutterlocalnotifications;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Pinned 22.3.2 cache contract. Do not replay missed one-shot debt notifications on reboot. */
public final class DebtReminderBootReceiver extends BroadcastReceiver {
  @Override
  public void onReceive(Context context, Intent intent) {
    String action = intent.getAction();
    if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
        && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
        && !"android.intent.action.QUICKBOOT_POWERON".equals(action)
        && !"com.htc.intent.action.QUICKBOOT_POWERON".equals(action)) return;
    String raw = context.getSharedPreferences("scheduled_notifications", Context.MODE_PRIVATE)
        .getString("scheduled_notifications", null);
    if (raw == null) return;
    try {
      JSONArray items = new JSONArray(raw);
      JSONArray retained = new JSONArray();
      boolean changed = false;
      long now = System.currentTimeMillis();
      for (int i = 0; i < items.length(); i++) {
        JSONObject item = items.getJSONObject(i);
        int id = item.optInt("id", -1);
        boolean owned = id >= 0x40000000
            && "debt_reminders_v1".equals(item.optString("channelId", ""))
            && item.optString("payload", "").matches("[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}")
            && "UTC".equals(item.optString("timeZoneName", ""))
            && item.isNull("repeatInterval") && item.isNull("repeatIntervalMilliseconds")
            && item.isNull("scheduledNotificationRepeatFrequency")
            && item.isNull("matchDateTimeComponents");
        if (owned && !DebtReminderBootPolicy.isFuture(
            item.optString("scheduledDateTime", ""), item.optString("timeZoneName", ""), now)) {
          changed = true;
        } else retained.put(item);
      }
      // Keep original JSON objects/unknown fields in foreign entries. Do not round-trip
      // the whole cache through the plugin's narrower NotificationDetails decoder.
      if (changed && !context.getSharedPreferences("scheduled_notifications", Context.MODE_PRIVATE)
          .edit().putString("scheduled_notifications", retained.toString()).commit()) return;
      FlutterLocalNotificationsPlugin.rescheduleNotifications(context);
    } catch (JSONException | RuntimeException error) {
      // Unknown cache/setup remains unscheduled until fresh authorized foreground reconciliation.
      // Never erase a durable application manifest or a foreign financial command.
    }
  }
}
