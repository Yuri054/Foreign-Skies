# Baseline

The measurements PLAN.md's steps are judged by, taken on v0.5.7 before any of the plan's rule changes (branch
`plan/review-fixes`, after step 0). Godot 4.7.2, headless. Regenerate with:

```
python tools/campaign.py --scenario jan_1900 --years 35 --seeds 0-9
python tools/campaign.py --scenario july_1914 --years 21 --seeds 0-9
python tools/campaign.py --scenario jan_1900 --years 16 --seeds 0-3 --bystander BEL
python tools/economy.py
```

## What it says

- **War resolution (step 1).** Every run cedes capitals (median 5 a run) and provinces with no land link to the new
  owner (median 6.5 from 1900, 13 from July 1914). France and Germany fight 1 to 15 months; most of their wars are
  under 8.
- **The road to 1914 (step 2).** The first war between great powers comes in 1902-1904 in 5 of 10 seeds from 1900.
- **After the war (step 4).** From 1922: no wars and no crises in any 1900 run or any July 1914 run; tension hardly
  moves (spread 0.2 and 1.55); a nation's focus tree is used up early in every run (an AI nation sits without a focus
  for 383 months from 1900, 215 from July 1914).
- **Money and armies (step 3b).** Great-power treasuries at peace hold about 11 months of revenue (median), 12-13.5 from 1922; armies
  three years after a war are as large as at its height (ratio 1.0).
- **The economy (step 3).** With the AI off, 1900-1914: building everything and taking every focus lifts GDP 14-24% over
  doing nothing; a 20% tax costs 6% of GDP and gives Germany £2.1bn (against £88M); 5% changes nothing but revenue;
  mobilizing to 40% in peace runs Germany £1.3bn into debt; Serbia's IC moves by nothing whatever it does.
- **Small nations (step 5).** A passive Belgium is asked 0.16 things a year.

## AI-only runs

jan_1900, 35 years, seeds 0-9, bystander ESP (545 s)

| Seed | First GP war | GP war months (median) | FRA-GER months | Capitals ceded | Detached cessions | Worst GP loss | Wars/yr from 1922 | Crises/yr from 1922 | Tension SD from 1922 | Treasury (months) | Treasury from 1922 | Army / last war peak | Longest idle focus | Bystander decisions/yr |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1902.11 | 6.4 | 7.9 | 4 | 11 | 0.06 | 0 | 0 | 0.2 | 12.1 | 12.7 | 1 | 383 | 0.03 |
| 1 | 1914.06 | 17.35 | 8.8 | 6 | 1 | 0.05 | 0 | 0 | 0.2 | 11.9 | 13.7 | 1 | 383 | 0.03 |
| 2 | 1913.02 | 6.2 | 7.4, 5 | 7 | 13 | 0.12 | 0 | 0 | 0.3 | 8.6 | 13.3 | 1 | 383 | 0.03 |
| 3 | 1903.1 | 4.95 | 0.8 | 5 | 6 | 0.09 | 0 | 0 | 0.2 | 15.1 | 23.5 | 1.04 | 383 | 0.06 |
| 4 | 1912.11 | 10.8 | 5.3, 5.9, 14.6 | 7 | 10 | 0.06 | 0 | 0 | 0.3 | 11.1 | 12.2 | 1 | 383 | 0.06 |
| 5 | 1904.01 | 9.4 | 9.6, 3.8 | 6 | 5 | 0.1 | 0 | 0 | 0.1 | 8.3 | 8.6 | 1 | 383 | 0.06 |
| 6 | 1913.02 | 6.3 | 6.3, 3 | 3 | 7 | 0.12 | 0 | 0 | 0.1 | 8.7 | 15.6 | 1 | 383 | 0.09 |
| 7 | 1914.06 | 12.3 | 11.8 | 4 | 5 | 0.08 | 0 | 0 | 0.3 | 12.2 | 14.1 | 0.92 | 383 | 0.03 |
| 8 | 1904.01 | 8.25 | 11.6, 4.9 | 5 | 13 | 0.15 | 0 | 0 | 0.1 | 8.4 | 8.3 | 1 | 383 | 0.06 |
| 9 | 1903.1 | 8.45 | 4.9 | 3 | 0 | 0.1 | 0 | 0 | 0.1 | 11.2 | 14.4 | 1.04 | 383 | 0.06 |
| **median** | 1908.06 | 8.35 |  | 5 | 6.5 | 0.095 | 0 | 0 | 0.2 | 11.15 | 13.5 | 1 | 383 | 0.06 |

july_1914, 21 years, seeds 0-9, bystander ESP (388 s)

| Seed | First GP war | GP war months (median) | FRA-GER months | Capitals ceded | Detached cessions | Worst GP loss | Wars/yr from 1922 | Crises/yr from 1922 | Tension SD from 1922 | Treasury (months) | Treasury from 1922 | Army / last war peak | Longest idle focus | Bystander decisions/yr |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1914.08 | 6 | 2.9, 3.9 | 7 | 16 | 0.14 | 0 | 0.21 | 1.2 | 9.5 | 10.5 | 1.04 | 215 | 0.19 |
| 1 | 1914.08 | 6 | 3.9 | 5 | 7 | 0.08 | 0 | 0 | 1.5 | 14.9 | 17.2 | 1.03 | 215 | 0 |
| 2 | 1914.08 | 5.45 | 6.8, 2.9 | 7 | 22 | 0.26 | 0 | 0.71 | 1.8 | 8.4 | 9.4 | 1.02 | 215 | 0.33 |
| 3 | 1914.08 | 6.8 | 6.8, 0.8 | 7 | 17 | 0.16 | 0 | 0 | 1.7 | 12.4 | 13.4 | 1 | 215 | 0 |
| 4 | 1914.08 | 8.9 | 9.9, 3.9 | 10 | 13 | 0.16 | 0 | 0.57 | 1.6 | 8.3 | 10.2 | 0.99 | 215 | 0.29 |
| 5 | 1914.08 | 6 | 4.9, 4.1 | 1 | 5 | 0.1 | 0 | 0 | 1.8 | 8.2 | 9.9 | 1 | 215 | 0 |
| 6 | 1914.08 | 7.9 | 6.8, 7.9 | 5 | 15 | 0.16 | 0 | 0.5 | 1.8 | 6.6 | 8.5 | 1 | 215 | 0.29 |
| 7 | 1914.08 | 5 | 3.9 | 5 | 1 | 0.09 | 0 | 0 | 0.1 | 15 | 18 | 1 | 215 | 0 |
| 8 | 1914.08 | 6.45 | 3.9 | 5 | 13 | 0.09 | 0 | 0 | 0.3 | 12.7 | 14.7 | 1.05 | 215 | 0 |
| 9 | 1914.08 | 5.95 | 3.9 | 5 | 6 | 0.09 | 0 | 0 | 0.2 | 14.6 | 16 | 1.08 | 215 | 0 |
| **median** | 1914.08 | 6 |  | 5 | 13 | 0.12 | 0 | 0 | 1.55 | 10.95 | 11.95 | 1.01 | 215 | 0 |

jan_1900, 16 years, seeds 0-3, bystander BEL (92 s)

| Seed | First GP war | GP war months (median) | FRA-GER months | Capitals ceded | Detached cessions | Worst GP loss | Wars/yr from 1922 | Crises/yr from 1922 | Tension SD from 1922 | Treasury (months) | Treasury from 1922 | Army / last war peak | Longest idle focus | Bystander decisions/yr |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1902.11 | 6.4 | 7.9 | 4 | 9 | 0.09 | - | - | - | 10.9 | - | 1 | 155 | 0.13 |
| 1 | 1914.06 | 10.8 | 12.8 | 5 | 0 | 0 | - | - | - | 8.8 | - | 1.14 | 155 | 0.13 |
| 2 | 1913.02 | 5.65 | 7.4, 3.9 | 3 | 5 | 0.12 | - | - | - | 4.3 | - | - | 155 | 0.19 |
| 3 | 1903.1 | 4.95 | 0.8 | 5 | 6 | 0.09 | - | - | - | 10.1 | - | 1.02 | 155 | 0.19 |
| **median** | 1908.06 | 6.025 |  | 4.5 | 5.5 | 0.09 |  |  |  | 9.45 |  | 1.02 | 155 | 0.16 |

## The economy alone

Economy policies, 14 years from the scenario's start, AI off (261 s)

**GER**

| Policy | GDP/mo | vs nothing | IC/day | vs nothing | Revenue/mo | Net/mo | Treasury | Development | Support | Built |
|---|---|---|---|---|---|---|---|---|---|---|
| passive | 196.2 | +0% | 265 | +0% | 19.70 | +0.54 | 88 | +15% | 70 | 0 |
| fact | 206.5 | +5% | 333 | +26% | 20.67 | -0.20 | 53 | +15% | 70 | 203 |
| rail | 219.2 | +12% | 292 | +10% | 21.94 | +1.19 | 147 | +15% | 70 | 341 |
| port | 198.2 | +1% | 268 | +1% | 21.21 | +1.90 | 269 | +15% | 70 | 56 |
| all | 222.1 | +13% | 356 | +34% | 23.67 | +1.48 | 234 | +15% | 70 | 302 |
| focus | 213.7 | +9% | 329 | +24% | 25.66 | +5.00 | 538 | +21% | 70 | 0 |
| all+focus | 242.9 | +24% | 433 | +63% | 30.75 | +6.17 | 698 | +21% | 70 | 354 |
| tax=0.05 | 196.2 | +0% | 265 | +0% | 9.89 | -16.81 | -1810 | +15% | 70 | 0 |
| tax=0.2 | 184.5 | -6% | 251 | -5% | 32.62 | +14.35 | 2100 | +8% | 68 | 0 |
| tax=0.4 | 112.4 | -43% | 161 | -39% | 29.41 | +16.60 | 3216 | -34% | 50 | 0 |
| mob=0.4 | 161.9 | -17% | 222 | -16% | 15.05 | -14.59 | -1312 | +15% | 38 | 0 |

**ITA**

| Policy | GDP/mo | vs nothing | IC/day | vs nothing | Revenue/mo | Net/mo | Treasury | Development | Support | Built |
|---|---|---|---|---|---|---|---|---|---|---|
| passive | 75.3 | +0% | 106 | +0% | 7.54 | +0.28 | 34 | +15% | 40 | 0 |
| fact | 77.8 | +3% | 123 | +16% | 7.78 | +0.13 | 19 | +15% | 40 | 82 |
| rail | 82.6 | +10% | 115 | +8% | 8.27 | +0.75 | 70 | +15% | 40 | 199 |
| port | 78.0 | +4% | 109 | +3% | 9.56 | +2.12 | 228 | +15% | 40 | 152 |
| all | 81.8 | +9% | 127 | +20% | 9.34 | +1.50 | 140 | +15% | 40 | 131 |
| focus | 82.5 | +10% | 133 | +25% | 8.26 | +0.60 | 54 | +23% | 40 | 0 |
| all+focus | 90.2 | +20% | 158 | +49% | 10.43 | +1.98 | 172 | +23% | 40 | 160 |
| tax=0.05 | 75.3 | +0% | 106 | +0% | 3.77 | -6.53 | -731 | +15% | 40 | 0 |
| tax=0.2 | 70.8 | -6% | 101 | -5% | 12.47 | +5.51 | 834 | +8% | 38 | 0 |
| tax=0.4 | 43.1 | -43% | 69 | -35% | 11.05 | +5.93 | 1250 | -34% | 20 | 0 |
| mob=0.4 | 64.8 | -14% | 94 | -11% | 6.48 | -5.84 | -676 | +15% | 40 | 0 |

**BEL**

| Policy | GDP/mo | vs nothing | IC/day | vs nothing | Revenue/mo | Net/mo | Treasury | Development | Support | Built |
|---|---|---|---|---|---|---|---|---|---|---|
| passive | 23.8 | +0% | 53 | +0% | 2.38 | -0.09 | -5 | +15% | 70 | 0 |
| fact | 25.4 | +7% | 65 | +23% | 2.54 | -0.31 | -23 | +15% | 70 | 45 |
| rail | 26.9 | +13% | 58 | +9% | 2.69 | +0.02 | 7 | +15% | 70 | 48 |
| port | 24.2 | +2% | 54 | +2% | 2.71 | +0.22 | 36 | +15% | 70 | 9 |
| all | 27.8 | +17% | 69 | +30% | 3.12 | +0.16 | 23 | +15% | 70 | 64 |
| focus | 25.9 | +9% | 59 | +11% | 2.59 | -0.09 | -4 | +15% | 70 | 0 |
| all+focus | 30.1 | +26% | 76 | +43% | 3.38 | +0.17 | 26 | +15% | 70 | 70 |
| tax=0.05 | 23.8 | +0% | 53 | +0% | 1.19 | -2.29 | -246 | +15% | 70 | 0 |
| tax=0.2 | 22.3 | -6% | 51 | -4% | 3.93 | +1.62 | 248 | +8% | 68 | 0 |
| tax=0.4 | 13.6 | -43% | 39 | -26% | 3.50 | +1.95 | 394 | -34% | 50 | 0 |
| mob=0.4 | 20.4 | -14% | 49 | -8% | 2.04 | -1.66 | -182 | +15% | 70 | 0 |

**SRB**

| Policy | GDP/mo | vs nothing | IC/day | vs nothing | Revenue/mo | Net/mo | Treasury | Development | Support | Built |
|---|---|---|---|---|---|---|---|---|---|---|
| passive | 2.8 | +0% | 22 | +0% | 0.28 | -0.15 | 2 | +15% | 75 | 0 |
| fact | 2.9 | +4% | 22 | +0% | 0.29 | -0.15 | 2 | +15% | 75 | 18 |
| rail | 3.1 | +11% | 22 | +0% | 0.31 | -0.13 | 4 | +15% | 75 | 44 |
| port | 2.8 | +0% | 22 | +0% | 0.28 | -0.15 | 2 | +15% | 75 | 0 |
| all | 3.0 | +7% | 22 | +0% | 0.30 | -0.14 | 2 | +15% | 75 | 22 |
| focus | 3.1 | +11% | 22 | +0% | 0.31 | -0.13 | 2 | +15% | 75 | 0 |
| all+focus | 3.2 | +14% | 22 | +0% | 0.32 | -0.13 | 3 | +15% | 75 | 22 |
| tax=0.05 | 2.8 | +0% | 22 | +0% | 0.14 | -0.41 | -29 | +15% | 22 | 0 |
| tax=0.2 | 2.6 | -7% | 22 | +0% | 0.46 | +0.04 | 34 | +8% | 73 | 0 |
| tax=0.4 | 1.6 | -43% | 21 | -5% | 0.41 | +0.00 | 46 | -34% | 48 | 0 |
| mob=0.4 | 2.8 | +0% | 22 | +0% | 0.28 | -0.32 | -40 | +15% | 51 | 0 |
