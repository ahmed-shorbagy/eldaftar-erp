package com.dexterous.flutterlocalnotifications;

import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;

/** OS feasibility only: never interprets a business deadline or marks debt paid. */
public final class DebtReminderBootPolicy {
  private DebtReminderBootPolicy() {}

  public static boolean isFuture(String wall, String zone, long deviceNowMillis) {
    try {
      return LocalDateTime.parse(wall).atZone(ZoneId.of(zone)).toInstant()
          .isAfter(Instant.ofEpochMilli(deviceNowMillis));
    } catch (DateTimeException | NullPointerException error) {
      return false;
    }
  }
}
