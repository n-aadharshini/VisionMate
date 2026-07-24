# VisionMate Manual Voice Test Checklist

Run these checks on a physical Android device. For every phrase, start from the
Speak screen, hold and release the microphone orb, say the phrase, and wait for
the spoken reply and resulting screen.

## Navigate

| Phrase | Expected result |
| --- | --- |
| Take me to T Nagar | Navigate opens; T Nagar is marked as the voice destination. |
| Give directions for Koyambedu | Navigate opens; Koyambedu is prioritized. |
| Where is Agni College? | Navigate opens; Agni College is prioritized. |
| I need to reach Marina Beach | Navigate opens; Marina Beach is prioritized. |
| Show me the way to Chennai Central | Navigate opens; Chennai Central is prioritized. |

## Travel

| Phrase | Expected result |
| --- | --- |
| Which bus goes to T Nagar? | Travel opens; T Nagar is marked as the voice destination. |
| Bus for Koyambedu | Travel opens; Koyambedu is prioritized. |
| When will the metro arrive? | Travel opens. |
| Find a train for Chennai Central | Travel opens; Chennai Central is prioritized. |
| Help me plan travel to Marina Beach | Travel opens; Marina Beach is prioritized. |

## Read

| Phrase | Expected result |
| --- | --- |
| Read this | Read opens. |
| What does this say? | Read opens. |
| Scan this label | Read opens. |
| Please read the text | Read opens. |
| Can you read this medicine label? | Read opens. |

## Help

| Phrase | Expected result |
| --- | --- |
| I fell down, help | Help opens with a calm spoken response. |
| Emergency, I need help | Help opens with a calm spoken response. |
| Send SOS | Help opens with a calm spoken response. |
| I feel unsafe | Help opens with a calm spoken response. |
| There is danger near me | Help opens with a calm spoken response. |

## Chat and clarification

| Phrase | Expected result |
| --- | --- |
| What is VisionMate? | A spoken answer plays, then the app returns to Speak. |
| I am nervous about going out alone | A reassuring spoken answer plays, then the app returns to Speak. |
| Is it going to rain today? | A brief, honest spoken answer plays, then the app returns to Speak. |
| Vanakkam Mate, take me to T Nagar | Navigate opens if speech recognition transcribes the destination. |
| Blue banana | The app asks the user to repeat, then returns to Speak. |

## Offline fallback

1. Turn off Wi-Fi and mobile data.
2. Repeat: `Take me to T Nagar`, `Which bus goes to Koyambedu`, `Read this`, and `I fell down, help`.
3. Confirm each request still reaches its expected screen using the keyword fallback.
4. Turn connectivity back on and repeat one phrase from each category to confirm the Groq path resumes.

## Accessibility checks

- Confirm the Android microphone permission dialog is announced by TalkBack.
- Confirm partial transcription is visible to a sighted helper while Listening is open.
- Confirm Cancel stops listening and returns to Speak without opening Processing.
- Confirm a spoken reply plays before each mode screen opens.
