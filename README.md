# edge-app-medicinskap-temp-monitoring
Edge app for monitoring temperature in medicine cabinets.

Denna är finansierad av Jönköpings kommun. Dokumentation därför på svenska.

Denna app använder metadata på funktioner för att sätta gränsvärden på skåpens temperatur. Om värdet överstiger eller understiger satta gränser skickas meddelanden via notifieringsmekanismen i IoT Open.

För att minimera risken för falska larm finns en funktion att larma först efter ett upprepat antal mätningar utenför gränsområdet. 

Följande metadata används:

```
max_value
min_value
repetitions 
```
När värdet är strikt större än `max_value` eller strikt mindre än `min_value` och har varit det `repetition` gånger så skickas en eller flera notifications. När värdet åter är normalt skickas ett återställningsmeddelande. Återställningsmeddelandet skickas direkt och alltså inte efter upprepade värden inom intervallet. Har ett återställningsmeddelande skickats återställs räknaren och värdet behöver åter vara utanför `min_` eller `max_` `repetition` gånger för att ett nytt meddelande skall skickas.`

## Notifieringar

För att skicka meddelanden används IoT Opens standardfunktion för meddelanden. Det består av två delar. Ett meddelande (message) och en eller flera utskick (notification outputs).

### Meddelande

Meddelandet ser ut så här, men kan modifieras efter tycke och smak. Notera att meddelandet innehåller två villkorade delar beroende på om det är ett larm- eller återställningsmeddelande.

```
{{ if eq .payload.notificationType "recovery" }}
{{.payload.dev.meta.name}} är åter inom rekommenderat intervall ({{.payload.func.meta.min_value}} - {{.payload.func.meta.max_value}}).
{{ else }}
Temperatur för kylskåp {{ .payload.dev.meta.name }} är utanför rekommenderat intervall ({{.payload.func.meta.min_value}} - {{.payload.func.meta.max_value}}). 
{{ end }}
Senast avläst temperatur: {{.payload.value}} grader.
```

När meddelandet kommer fram ser det ut så här:
 
> Temperatur för kylskåp Medicinskåp 5 är utanför rekommenderat intervall (2 - 8). 
>
> Senast avläst temperatur: 12.4 grader.

Eller:

> Medicinskåp 5 är åter inom rekommenderat intervall (2 - 8). 
>
> Senast avläst temperatur: 7.4 grader.

### Utckick

Ett utskick bestämmer till vem eller vilka och hur ett meddelande skall skickas. Till exempel skall det skickas med e-post till några olika e-postadresser eller så skall det skickas med SMS till några olika telefonnummer.

Både SMS och e-post skall ha en metadata som heter `recipients` som innehåller en kommaseparerad lista med telefonnummer alternativt e-postadresser.

E-post behöver också en metadata `subject` som skall vara ärendet i brevet. Man kan sätta ett eget ärende, eller skriva `{{.payload.subject}}` för att låta denna app bestämma ärenderaden.

Här följer skärmdumpar på hur konfigurationen för dem kan se ut i detta fall.

![Bild på meddelandet](images/meddelande.png?raw=true "Meddelande")

![Bild på utskick](images/utskick.png?raw=true "Utskick")


## Begränsningar

Om appen skulle starta om så kommer räknaren som håller reda på hur många mätvärden det varit utanför aktuellt gränsvärde att nollställas. Det kan i specialfall göras att tiden till larm förlängs eller att det kommer ett extra larm till för ett skåp som det redan larmats om.
