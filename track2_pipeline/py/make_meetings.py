"""Write data/meetings.csv from the Federal Reserve FOMC calendar.
decision_date = last day of the meeting (statement day).
effective_date = next US federal business day, the first day EFFR reflects the decision.
status = "tentative" for 2027 and later, as marked on the Fed page."""
import pandas as pd
from pandas.tseries.holiday import USFederalHolidayCalendar
from pandas.tseries.offsets import CustomBusinessDay
from common import MEETINGS

# source: https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm (page last updated 2026-09-16)
DECISIONS = """
2025-01-29 2025-03-19 2025-05-07 2025-06-18 2025-07-30 2025-09-17 2025-10-29 2025-12-10
2026-01-28 2026-03-18 2026-04-29 2026-06-17 2026-07-29 2026-09-16 2026-10-28 2026-12-09
2027-01-27 2027-03-17 2027-04-28 2027-06-09 2027-07-28 2027-09-15 2027-10-27 2027-12-08
2028-01-26
""".split()

# business-day offset that skips weekends and federal holidays (2025-06-18 -> 2025-06-20 because of Juneteenth)
bd = CustomBusinessDay(calendar=USFederalHolidayCalendar())
rows = []
for d in DECISIONS:
    dd = pd.Timestamp(d)
    eff = dd + bd
    rows.append(dict(meeting=dd.strftime("%Y-%m"), decision_date=dd.date(), effective_date=eff.date(),
                     status="tentative" if dd.year >= 2027 else "scheduled/held"))
pd.DataFrame(rows).to_csv(MEETINGS, index=False)
print(pd.read_csv(MEETINGS).to_string(index=False))
