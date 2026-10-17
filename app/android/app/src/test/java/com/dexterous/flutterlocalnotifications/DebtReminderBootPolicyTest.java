package com.dexterous.flutterlocalnotifications;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import java.time.Instant;
import org.junit.Test;

public class DebtReminderBootPolicyTest {
  private final long now = Instant.parse("2026-10-15T10:00:00Z").toEpochMilli();
  @Test public void rebootKeepsFutureAndRejectsMissedOrEqualRequests() {
    assertTrue(DebtReminderBootPolicy.isFuture("2026-10-15T10:01:00", "UTC", now));
    assertFalse(DebtReminderBootPolicy.isFuture("2026-10-15T10:00:00", "UTC", now));
    assertFalse(DebtReminderBootPolicy.isFuture("2026-10-14T10:00:00", "UTC", now));
  }
  @Test public void invalidOrUnknownCacheDoesNotCauseCatchUp() {
    assertFalse(DebtReminderBootPolicy.isFuture("unknown", "UTC", now));
    assertFalse(DebtReminderBootPolicy.isFuture("2026-10-15T11:00:00", "unknown", now));
    assertFalse(DebtReminderBootPolicy.isFuture(null, "UTC", now));
  }
}
