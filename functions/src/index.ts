/**
 * Cloud Functions — Exercise Kitchen (MVP)
 *
 * Ces fonctions portent toute la logique qui ne peut pas être confiée
 * en sécurité au client Flutter :
 *  - createAdherentAccount : création de compte par un coach (section 3 des
 *    spécifications techniques) via l'Admin SDK, sans jamais faire perdre
 *    sa session au coach connecté.
 *  - registerForSlot / cancelRegistration : inscriptions/désinscriptions
 *    transactionnelles avec gestion de la capacité et de la liste d'attente
 *    (section 2.2 / 2.2bis).
 *
 * Génération des créneaux collectifs (section 1.3 : "fixes d'une semaine à
 * l'autre") : entièrement côté CLIENT depuis le 23 juillet 2026
 * (`PlanningRepository.ensureCollectiveSlotsForWeek`/`kDefaultCollectiveSchedule`
 * côté Flutter), appelée à chaque ouverture du planning coach — PAS ici.
 * **Attention (12 août 2026, bug corrigé)** : ce fichier contenait encore
 * jusqu'à cette date une ANCIENNE Cloud Function planifiée
 * `generateWeeklySlots`, qui lisait une collection Firestore `courses`
 * (système d'avant l'introduction de `kDefaultCollectiveSchedule`, jamais
 * nettoyée) et régénérait chaque lundi à 00h05 des créneaux collectifs
 * obsolètes (dont les créneaux 18h/12 places du lundi et vendredi que
 * Margaux supprimait manuellement, en vain — ils réapparaissaient à chaque
 * nouvelle semaine). Cette fonction — ainsi que la collection `courses`,
 * plus lue par aucun code — est désormais un système mort, entièrement
 * supprimé : la génération des créneaux collectifs ne vit plus QUE côté
 * client, à un seul endroit. Ne jamais réintroduire de génération de
 * créneaux collectifs côté Cloud Functions sans supprimer d'abord
 * l'équivalent côté client (ou inversement) — avoir 2 systèmes actifs en
 * parallèle est exactement ce qui a causé ce bug.
 *
 * Notifications push (FCM, section 4) : téléphone uniquement (pas
 * d'email/SMS), envoyées par les fonctions ci-dessous :
 *  - promotion liste d'attente → inscrit (dans `cancelRegistration`) ;
 *  - créneau collectif/duo à un seul inscrit — `checkSingleRegistrantSlots`
 *    (24h avant à l'unique inscrit.e ; aux autres adhérents de la formule à
 *    24h ET 4h avant, depuis le 18 août 2026 — plus d'exception le lundi) ;
 *  - créneau collectif/duo à moins de 2 inscrits, 4h avant, aux coachs —
 *    `checkLowRegistrationSlotsForCoach` ("Manque de monde") ;
 *  - rappel de cours 2h avant à l'adhérent inscrit — `sendCourseReminders` ;
 *  - rappel Rekovery 1h avant, aux coachs — `sendRekoveryReminders` ;
 *  - création/modification d'un workshop ou d'une fermeture, à tout le
 *    monde — `onSlotCreated`/`onSlotUpdated`/`onClosureCreated`/
 *    `onClosureUpdated` ;
 *  - modification/suppression d'un cours duo/individuel, aux adhérents
 *    concernés — `onSlotUpdated`/`onSlotDeleted` ;
 *  - double inscription le même jour (hors Rekovery), à l'adhérent
 *    concerné — instantané (`onRegistrationCreated`/`onRegistrationUpdated`)
 *    ET rappelé 24h avant le premier cours du jour concerné (depuis le 18
 *    août 2026) — `checkSameDayDoubleBookingReminders`.
 *
 * Les tokens FCM des appareils vivent dans `users/{uid}.fcmTokens` (tableau,
 * enregistré côté client — voir `push_notification_service.dart`). Un token
 * qui ne répond plus (désinstallation...) n'est pas nettoyé automatiquement
 * dans ce MVP : l'envoi échoue silencieusement pour ce token (log
 * d'avertissement), sans bloquer les autres destinataires.
 */

import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();

const REGION = "australia-southeast1";

function generateTemporaryPassword(): string {
  // Mot de passe temporaire lisible mais suffisamment fort ; l'adhérent doit
  // de toute façon le remplacer dès la première connexion (voir
  // ChangePasswordScreen côté Flutter).
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  let out = "";
  for (let i = 0; i < 12; i++) {
    out += chars[Math.floor(Math.random() * chars.length)];
  }
  return out;
}

async function requireCoach(uid: string | undefined): Promise<void> {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }
  const doc = await db.collection("users").doc(uid).get();
  const role = doc.data()?.role;
  const status = doc.data()?.status;
  if (role !== "coach" || status !== "active") {
    throw new HttpsError(
      "permission-denied",
      "Seul un coach actif peut effectuer cette action."
    );
  }
}

// ---------------------------------------------------------------------
// Notifications push (FCM) — helpers partagés
// ---------------------------------------------------------------------

/**
 * Envoie une notification push à une liste de tokens (dédoublonnée), par
 * lots de 500 (limite de `sendEachForMulticast`). N'échoue jamais
 * bruyamment : un token invalide ne fait que logger un avertissement, sans
 * empêcher l'envoi aux autres destinataires ni faire échouer la fonction
 * appelante.
 */
/**
 * Codes d'erreur FCM signifiant que le token ne correspond plus à AUCUNE
 * installation vivante de l'app (app désinstallée, ou réinstallée avec une
 * config Firebase différente — ce qui invalide l'ancien token) : plus
 * aucune notification ne pourra jamais y arriver, il ne sert donc à rien de
 * le garder. À distinguer d'une erreur transitoire (réseau, quota...), qui
 * elle ne doit PAS entraîner de suppression.
 */
const DEAD_TOKEN_ERROR_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/**
 * Retire [token] du tableau `fcmTokens` de TOUS les utilisateurs qui
 * l'auraient encore (normalement un seul, mais `array-contains` couvre le
 * cas où plusieurs comptes auraient été connectés sur le même appareil
 * sans que l'ancien token ait été retiré entretemps). Best-effort : une
 * erreur ici ne doit jamais faire échouer l'envoi des autres notifications
 * (voir [sendPushToTokens]).
 */
async function pruneDeadToken(token: string): Promise<void> {
  try {
    const snap = await db.collection("users").where("fcmTokens", "array-contains", token).get();
    await Promise.all(
      snap.docs.map((doc) =>
        doc.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(token) })
      )
    );
  } catch (err) {
    logger.error("pruneDeadToken: échec du nettoyage", err);
  }
}

async function sendPushToTokens(
  tokens: string[],
  title: string,
  body: string
): Promise<void> {
  const unique = Array.from(new Set(tokens)).filter((t) => !!t);
  if (unique.length === 0) {
    // Avertissement de diagnostic (17 août 2026) : si un destinataire attendu
    // ne reçoit jamais de notification, ce log (visible dans la Console
    // Firebase → Functions → Journaux) permet de vérifier si la fonction a
    // bien tenté d'envoyer, mais n'avait AUCUN token enregistré (permission
    // refusée sur l'appareil, `PushNotificationService.registerForUser`
    // jamais appelé, ou `fcmTokens` absent/vide sur `users/{uid}`) — plutôt
    // qu'un problème côté envoi lui-même.
    logger.warn(`sendPushToTokens: aucun token disponible pour "${title}" — envoi ignoré.`);
    return;
  }

  for (let i = 0; i < unique.length; i += 500) {
    const batch = unique.slice(i, i + 500);
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
      });
      const deadTokens: string[] = [];
      response.responses.forEach((r, idx) => {
        if (!r.success) {
          logger.warn(`Échec d'envoi push pour un token`, {
            token: batch[idx],
            error: r.error?.message,
          });
          // Nettoyage automatique (19 août 2026, demande de Margaux — suite
          // au diagnostic des notifications iPhone absentes) : un token
          // "NotRegistered"/invalide est mort pour toujours (typiquement un
          // ancien token laissé par une réinstallation avec une config
          // Firebase différente, ex. changement de bundle ID) — le garder
          // ne fait que polluer `fcmTokens` et générer cet avertissement à
          // chaque futur envoi, sans jamais empêcher les tokens valides de
          // recevoir leur notification (chaque token est indépendant).
          if (r.error?.code && DEAD_TOKEN_ERROR_CODES.has(r.error.code)) {
            deadTokens.push(batch[idx]);
          }
        }
      });
      if (deadTokens.length > 0) {
        await Promise.all(deadTokens.map((t) => pruneDeadToken(t)));
      }
    } catch (err) {
      logger.error("Échec de l'envoi push (lot)", err);
    }
  }
}

/**
 * Tokens FCM de plusieurs utilisateurs identifiés par leur uid (lu par lots
 * de 30, limite Firestore de `whereIn`/`documentId() in`).
 *
 * [prefKey], si fourni, exclut un utilisateur ayant explicitement désactivé
 * ce type de notification (`notificationPrefs.<prefKey> === false` — voir
 * `adherent_profile_screen.dart`/`notification_settings_screen.dart` côté
 * Flutter). Absent ou `true` = activé, pour ne jamais couper les
 * notifications de quelqu'un qui n'a jamais ouvert son profil (coachs
 * compris : ils n'ont pas de préférences, donc jamais filtrés).
 */
async function getTokensForUids(uids: string[], prefKey?: string): Promise<string[]> {
  const unique = Array.from(new Set(uids)).filter((u) => !!u);
  if (unique.length === 0) return [];
  const tokens: string[] = [];
  for (let i = 0; i < unique.length; i += 30) {
    const chunk = unique.slice(i, i + 30);
    const snap = await db
      .collection("users")
      .where(admin.firestore.FieldPath.documentId(), "in", chunk)
      .get();
    snap.docs.forEach((doc) => {
      const data = doc.data();
      if (prefKey) {
        const prefs = data.notificationPrefs as Record<string, boolean> | undefined;
        if (prefs && prefs[prefKey] === false) return;
      }
      const t = data.fcmTokens as string[] | undefined;
      if (t) tokens.push(...t);
    });
  }
  return tokens;
}

/**
 * Tokens FCM de tous les adhérents actifs souscrivant à [formula]
 * ('collectif' ou 'duo'), en excluant [excludeUids] (ex. l'unique inscrit
 * actuel du créneau, qui n'a pas besoin d'être invité à rejoindre son
 * propre cours).
 *
 * Filtre `status`/`formulas` en mémoire plutôt que par une requête Firestore
 * composée (`role` + `status` + `array-contains`) : évite d'avoir besoin
 * d'un index composite supplémentaire, et le nombre d'adhérents d'une seule
 * salle reste de toute façon faible.
 */
async function getTokensForFormula(
  formula: string,
  excludeUids: string[] = [],
  prefKey?: string
): Promise<string[]> {
  const snap = await db.collection("users").where("role", "==", "adherent").get();
  const tokens: string[] = [];
  snap.docs.forEach((doc) => {
    if (excludeUids.includes(doc.id)) return;
    const data = doc.data();
    if (data.status !== "active") return;
    const formulas = (data.formulas as string[] | undefined) ?? [];
    if (!formulas.includes(formula)) return;
    if (prefKey) {
      const prefs = data.notificationPrefs as Record<string, boolean> | undefined;
      if (prefs && prefs[prefKey] === false) return;
    }
    const t = data.fcmTokens as string[] | undefined;
    if (t) tokens.push(...t);
  });
  return tokens;
}

/** Tokens FCM de tous les comptes actifs (coachs ET adhérents). [prefKey],
 * si fourni, exclut un adhérent ayant désactivé ce type — voir
 * [getTokensForUids] pour le détail du comportement par défaut. */
async function getAllActiveTokens(prefKey?: string): Promise<string[]> {
  const snap = await db.collection("users").where("status", "==", "active").get();
  const tokens: string[] = [];
  snap.docs.forEach((doc) => {
    const data = doc.data();
    if (prefKey) {
      const prefs = data.notificationPrefs as Record<string, boolean> | undefined;
      if (prefs && prefs[prefKey] === false) return;
    }
    const t = data.fcmTokens as string[] | undefined;
    if (t) tokens.push(...t);
  });
  return tokens;
}

/** Tokens FCM des deux coachs (filtre `status` fait en mémoire — deux
 * coachs seulement, pas besoin d'index composite pour ça). */
async function getCoachTokens(): Promise<string[]> {
  const snap = await db.collection("users").where("role", "==", "coach").get();
  const tokens: string[] = [];
  snap.docs.forEach((doc) => {
    const data = doc.data();
    if (data.status !== "active") return;
    const t = data.fcmTokens as string[] | undefined;
    if (t) tokens.push(...t);
  });
  return tokens;
}

/** Nouvelle-Calédonie (Nouméa) : UTC+11 toute l'année, pas de changement
 * d'heure saisonnier — donc pas de gestion DST à prévoir ici. */
const NOUMEA_TIME_ZONE = "Pacific/Noumea";

/** Combine la date d'un créneau (minuit du jour concerné) avec son heure de
 * début ("HH:mm") en un instant précis — `slotDate` étant un `Timestamp`
 * (donc déjà un instant absolu), on lui ajoute simplement les minutes
 * écoulées depuis minuit ce jour-là. */
function slotStartInstant(slotDate: admin.firestore.Timestamp, startTime: string): Date {
  const [hh, mm] = startTime.split(":").map((n) => parseInt(n, 10));
  return new Date(slotDate.toDate().getTime() + (hh * 60 + mm) * 60 * 1000);
}

/** "lundi 20/07 à 18h00", pour les messages de notification. */
function formatSlotWhen(slotDate: admin.firestore.Timestamp, startTime: string): string {
  const d = slotDate.toDate();
  const weekday = new Intl.DateTimeFormat("fr-FR", {
    timeZone: NOUMEA_TIME_ZONE,
    weekday: "long",
  }).format(d);
  const dayMonth = new Intl.DateTimeFormat("fr-FR", {
    timeZone: NOUMEA_TIME_ZONE,
    day: "2-digit",
    month: "2-digit",
  }).format(d);
  return `${weekday} ${dayMonth} à ${startTime.replace(":", "h")}`;
}

/** "lundi 20/07", sans l'heure — utilisé pour l'alerte de double
 * inscription le même jour (section nouvelle, voir plus bas), qui concerne
 * potentiellement deux créneaux à des heures différentes. */
function formatDayOnly(date: admin.firestore.Timestamp): string {
  const d = date.toDate();
  const weekday = new Intl.DateTimeFormat("fr-FR", {
    timeZone: NOUMEA_TIME_ZONE,
    weekday: "long",
  }).format(d);
  const dayMonth = new Intl.DateTimeFormat("fr-FR", {
    timeZone: NOUMEA_TIME_ZONE,
    day: "2-digit",
    month: "2-digit",
  }).format(d);
  return `${weekday} ${dayMonth}`;
}

/** Vrai si [date] correspond au jour calendaire actuel, une fois interprétée
 * dans le fuseau de Nouméa — utilisé pour alléger les messages concernant un
 * créneau du jour même (pas besoin de redonner la date). */
function isTodayInNoumea(date: Date): boolean {
  const fmt: Intl.DateTimeFormatOptions = {
    timeZone: NOUMEA_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  };
  return (
    new Intl.DateTimeFormat("fr-FR", fmt).format(date) ===
    new Intl.DateTimeFormat("fr-FR", fmt).format(new Date())
  );
}

/** "12h" (sans minutes si l'heure est ronde) ou "16h30" — format court de
 * l'heure, utilisé dans les messages concernant le jour même (26/07/2026,
 * demande de Margaux). */
function formatTimeShort(hhmm: string): string {
  const [hh, mm] = hhmm.split(":");
  return mm === "00" ? `${hh}h` : `${hh}h${mm}`;
}

/** "lundi 20/08" — jour de la semaine + date courte (JJ/MM), utilisé dans
 * les messages Rekovery (18 août 2026, demande de Margaux) pour préciser le
 * jour de la semaine en plus de la date déjà affichée. */
function weekdayShortDate(date: admin.firestore.Timestamp): string {
  const d = date.toDate();
  const weekday = new Intl.DateTimeFormat("fr-FR", {
    timeZone: NOUMEA_TIME_ZONE,
    weekday: "long",
  }).format(d);
  const dayMonth = new Intl.DateTimeFormat("fr-FR", {
    timeZone: NOUMEA_TIME_ZONE,
    day: "2-digit",
    month: "2-digit",
  }).format(d);
  return `${weekday} ${dayMonth}`;
}

/** "mercredi 23 août" (ou "mercredi 1er août" pour le 1ᵉʳ du mois) — jour de
 * la semaine + date en toutes lettres, utilisé dans les messages concernant
 * un cours (18 août 2026, demande de Margaux) — plus lisible que le JJ/MM
 * pour ces messages-là. */
function weekdayFullDate(date: admin.firestore.Timestamp): string {
  const d = date.toDate();
  const weekday = new Intl.DateTimeFormat("fr-FR", {
    timeZone: NOUMEA_TIME_ZONE,
    weekday: "long",
  }).format(d);
  const dayNum = parseInt(
    new Intl.DateTimeFormat("fr-FR", { timeZone: NOUMEA_TIME_ZONE, day: "numeric" }).format(d),
    10
  );
  const dayLabel = dayNum === 1 ? "1er" : `${dayNum}`;
  const month = new Intl.DateTimeFormat("fr-FR", {
    timeZone: NOUMEA_TIME_ZONE,
    month: "long",
  }).format(d);
  return `${weekday} ${dayLabel} ${month}`;
}

/** "du mercredi 23 août" — [weekdayFullDate] précédé de "du ", pour
 * l'insérer directement après un nom de cours ("Collectif du mercredi 23
 * août"). */
function weekdayFullDateDu(date: admin.firestore.Timestamp): string {
  return `du ${weekdayFullDate(date)}`;
}

/** "d'aujourd'hui" (jour même) ou "du mercredi 23 août" (autre jour) — à
 * insérer directement après un nom de cours (18 août 2026, demande de
 * Margaux — remplace l'ancienne clause "de 12h"/"à ... lundi 20/07 à
 * 12h00", voir [registeredClause]). */
function courseDayPhrase(slotDate: admin.firestore.Timestamp): string {
  return isTodayInNoumea(slotDate.toDate()) ? "d'aujourd'hui" : weekdayFullDateDu(slotDate);
}

/** "au Collectif d'aujourd'hui à 12h" (jour même) ou "au Collectif du
 * mercredi 23 août à 12h" (autre jour), à insérer après "Tu es inscrit.e "
 * dans les messages de confirmation de place (nouvelle place directe,
 * promotion liste d'attente, rappel 2h avant) — refonte du 18 août 2026
 * (demande de Margaux, remplace la version du 26/07/2026 qui utilisait "de
 * 12h"/"à Collectif lundi 20/07 à 12h00"). */
function registeredClause(
  courseTitle: string,
  slotDate: admin.firestore.Timestamp,
  startTime: string
): string {
  return `au ${courseTitle} ${courseDayPhrase(slotDate)} à ${formatTimeShort(startTime)}`;
}

/** "de demain à 18h" ou "de 18h" (jour même, cas du lundi où l'alerte part 4h
 * avant plutôt que 24h) — utilisé dans le message envoyé à l'unique
 * inscrit(e) d'un créneau, ET dans l'invitation envoyée aux autres adhérents
 * pour qu'ils le/la rejoignent (voir `checkSingleRegistrantSlots`) — corrigé
 * le 17 août 2026 (demande de Margaux) : la branche "demain" ne comportait
 * pas de "à" avant l'heure ("de demain 18h" → "de demain à 18h", cohérent
 * avec la branche jour même "de 18h"). */
function loneRegistrantClause(slotDate: admin.firestore.Timestamp, startTime: string): string {
  const timeShort = formatTimeShort(startTime);
  return isTodayInNoumea(slotDate.toDate()) ? `de ${timeShort}` : `de demain à ${timeShort}`;
}

/** "le 20/07" ou "du 20/07 au 22/07" selon que la fermeture dure un seul
 * jour ou plusieurs. */
function formatClosureWhen(
  startDate: admin.firestore.Timestamp,
  endDate: admin.firestore.Timestamp
): string {
  const fmt = (d: Date) =>
    new Intl.DateTimeFormat("fr-FR", {
      timeZone: NOUMEA_TIME_ZONE,
      day: "2-digit",
      month: "2-digit",
    }).format(d);
  const start = fmt(startDate.toDate());
  const end = fmt(endDate.toDate());
  return start === end ? `le ${start}` : `du ${start} au ${end}`;
}

const FORMULA_BY_SLOT_TYPE: Record<string, string> = {
  collective: "collectif",
  duo: "duo",
};

/**
 * Coach uniquement. Crée le compte Firebase Auth + le document Firestore
 * `users/{uid}` d'un nouvel adhérent, avec `needsPasswordChange: true` et
 * `consentAccepted: false` pour déclencher le parcours de première
 * connexion (mot de passe puis écran RGPD).
 */
export const createAdherentAccount = onCall(
  { region: REGION },
  async (request) => {
    await requireCoach(request.auth?.uid);

    const { firstName, lastName, email, phone, formulas, rekoveryCreditsRemaining } =
      request.data as {
        firstName?: string;
        lastName?: string;
        email?: string;
        phone?: string | null;
        formulas?: string[];
        rekoveryCreditsRemaining?: number | null;
      };

    if (!firstName || !lastName || !email) {
      throw new HttpsError(
        "invalid-argument",
        "Prénom, nom et email sont requis."
      );
    }

    // Carnet Rekovery initial (7 août 2026) : uniquement pertinent pour un
    // adhérent "Rekovery seul" (une seule formule, "rekovery") — recalculé
    // ici côté serveur (pas de confiance dans un booléen envoyé par le
    // client) plutôt qu'un accès illimité qui n'a pas de carnet à gérer.
    const isRekoverySoloOnly =
      (formulas ?? []).length === 1 && (formulas ?? []).includes("rekovery");
    const initialCredits =
      isRekoverySoloOnly && rekoveryCreditsRemaining != null
        ? Math.max(0, Math.trunc(rekoveryCreditsRemaining))
        : null;

    const temporaryPassword = generateTemporaryPassword();

    const userRecord = await auth.createUser({
      email,
      password: temporaryPassword,
      displayName: `${firstName} ${lastName}`,
    });

    await db.collection("users").doc(userRecord.uid).set({
      firstName,
      lastName,
      email,
      phone: phone ?? null,
      role: "adherent",
      status: "active",
      needsPasswordChange: true,
      consentAccepted: false,
      consentAcceptedAt: null,
      consentVersion: null,
      formulas: formulas ?? [],
      rekoveryCreditsRemaining: initialCredits,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Envoi de l'email avec le mot de passe temporaire.
    // Repose sur l'extension Firebase "Trigger Email from Firestore"
    // (voir README.md, étape 5) qui surveille la collection `mail`.
    let emailSent = false;
    try {
      await db.collection("mail").add({
        to: email,
        message: {
          subject: "Bienvenue chez Exercise Kitchen — accès à l'application",
          text:
            `Bonjour ${firstName},\n\n` +
            "Ton coach vient de créer ton espace sur l'application Exercise Kitchen.\n\n" +
            `Email : ${email}\n` +
            `Mot de passe temporaire : ${temporaryPassword}\n\n` +
            "Connecte-toi puis choisis un mot de passe personnel dès ta première connexion.\n\n" +
            "À bientôt en salle !",
        },
      });
      emailSent = true;
    } catch (err) {
      logger.error("Échec de la mise en file d'attente de l'email", err);
    }

    return { uid: userRecord.uid, emailSent };
  }
);

/**
 * Inscrit l'utilisateur authentifié à un créneau, dans une transaction :
 * si le créneau a de la place, la place est confirmée ; sinon l'adhérent
 * est ajouté en fin de liste d'attente (section 2.2bis).
 */
export const registerForSlot = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");

    const { slotId } = request.data as { slotId?: string };
    if (!slotId) throw new HttpsError("invalid-argument", "slotId requis.");

    const slotRef = db.collection("slots").doc(slotId);

    // Un adhérent ne peut avoir qu'une seule inscription active par créneau.
    const existing = await db
      .collection("registrations")
      .where("slotId", "==", slotId)
      .where("userId", "==", uid)
      .limit(1)
      .get();
    if (!existing.empty) {
      throw new HttpsError(
        "already-exists",
        "Tu es déjà inscrit.e ou en liste d'attente sur ce créneau."
      );
    }

    return db.runTransaction(async (tx) => {
      const slotSnap = await tx.get(slotRef);
      if (!slotSnap.exists) {
        throw new HttpsError("not-found", "Ce créneau n'existe plus.");
      }
      const slot = slotSnap.data()!;
      const registeredCount = slot.registeredCount ?? 0;
      const waitlistCount = slot.waitlistCount ?? 0;
      const capacity = slot.capacity ?? 0;

      const regRef = db.collection("registrations").doc();
      const confirmed = registeredCount < capacity;

      tx.set(regRef, {
        slotId,
        userId: uid,
        status: confirmed ? "confirmed" : "waitlisted",
        waitlistPosition: confirmed ? null : waitlistCount + 1,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.update(slotRef, confirmed
        ? { registeredCount: registeredCount + 1 }
        : { waitlistCount: waitlistCount + 1 });

      return { status: confirmed ? "confirmed" : "waitlisted" };
    });
  }
);

/**
 * Coach : inscrit un adhérent précis (pas l'appelant lui-même) à un
 * créneau — utilisé pour préremplir à l'avance les 2 places d'un cours duo
 * (section 1.3, demande du 7 août 2026) quand le coach connaît déjà les
 * noms. C'est une VRAIE inscription (compte dans la capacité, bloque la
 * place comme n'importe quelle inscription libre) — Margaux a confirmé ce
 * choix plutôt qu'une simple note, voir échange du 7 août 2026 — d'où une
 * nouvelle Cloud Function plutôt qu'une réutilisation de [registerForSlot],
 * qui n'inscrit que `request.auth.uid` (l'appelant) et ne prend aucun
 * paramètre pour inscrire un tiers.
 *
 * Même logique transactionnelle que [registerForSlot] (confirmée si de la
 * place, sinon liste d'attente) — un coach pourrait en théorie préremplir
 * un créneau déjà complet, auquel cas l'adhérent atterrit en liste
 * d'attente comme n'importe qui.
 */
export const coachRegisterAdherentForSlot = onCall(
  { region: REGION },
  async (request) => {
    await requireCoach(request.auth?.uid);

    const { slotId, adherentUid } = request.data as {
      slotId?: string;
      adherentUid?: string;
    };
    if (!slotId || !adherentUid) {
      throw new HttpsError("invalid-argument", "slotId et adherentUid requis.");
    }

    const slotRef = db.collection("slots").doc(slotId);

    const existing = await db
      .collection("registrations")
      .where("slotId", "==", slotId)
      .where("userId", "==", adherentUid)
      .limit(1)
      .get();
    if (!existing.empty) {
      throw new HttpsError(
        "already-exists",
        "Cet.te adhérent.e est déjà inscrit.e ou en liste d'attente sur ce créneau."
      );
    }

    return db.runTransaction(async (tx) => {
      const slotSnap = await tx.get(slotRef);
      if (!slotSnap.exists) {
        throw new HttpsError("not-found", "Ce créneau n'existe plus.");
      }
      const slot = slotSnap.data()!;
      const registeredCount = slot.registeredCount ?? 0;
      const waitlistCount = slot.waitlistCount ?? 0;
      const capacity = slot.capacity ?? 0;

      const regRef = db.collection("registrations").doc();
      const confirmed = registeredCount < capacity;

      tx.set(regRef, {
        slotId,
        userId: adherentUid,
        status: confirmed ? "confirmed" : "waitlisted",
        waitlistPosition: confirmed ? null : waitlistCount + 1,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.update(slotRef, confirmed
        ? { registeredCount: registeredCount + 1 }
        : { waitlistCount: waitlistCount + 1 });

      return { status: confirmed ? "confirmed" : "waitlisted" };
    });
  }
);

/**
 * Annule l'inscription de l'utilisateur authentifié. Si la place libérée
 * était confirmée et qu'une liste d'attente existe, la personne suivante
 * est automatiquement promue (section 2.2bis) — et notifiée par push.
 */
export const cancelRegistration = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");

    const { registrationId } = request.data as { registrationId?: string };
    if (!registrationId) {
      throw new HttpsError("invalid-argument", "registrationId requis.");
    }

    const regRef = db.collection("registrations").doc(registrationId);

    const result = await db.runTransaction(async (tx) => {
      const regSnap = await tx.get(regRef);
      if (!regSnap.exists) {
        throw new HttpsError("not-found", "Inscription introuvable.");
      }
      const registration = regSnap.data()!;
      if (registration.userId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Tu ne peux annuler que tes propres inscriptions."
        );
      }

      const slotRef = db.collection("slots").doc(registration.slotId);
      const slotSnap = await tx.get(slotRef);
      if (!slotSnap.exists) {
        tx.delete(regRef);
        return { promoted: false as const };
      }
      const slot = slotSnap.data()!;
      const wasConfirmed = registration.status === "confirmed";

      tx.delete(regRef);

      if (!wasConfirmed) {
        // Désinscription d'une personne en liste d'attente : on décrémente
        // simplement le compteur, sans toucher aux places confirmées.
        tx.update(slotRef, {
          waitlistCount: Math.max((slot.waitlistCount ?? 1) - 1, 0),
        });
        return { promoted: false as const };
      }

      // Une place confirmée se libère : on cherche le premier de la liste
      // d'attente pour ce créneau.
      const waitlistQuery = await db
        .collection("registrations")
        .where("slotId", "==", registration.slotId)
        .where("status", "==", "waitlisted")
        .orderBy("waitlistPosition", "asc")
        .limit(1)
        .get();

      if (waitlistQuery.empty) {
        tx.update(slotRef, {
          registeredCount: Math.max((slot.registeredCount ?? 1) - 1, 0),
        });
        return { promoted: false as const };
      }

      const nextInLine = waitlistQuery.docs[0];
      tx.update(nextInLine.ref, {
        status: "confirmed",
        waitlistPosition: null,
      });
      tx.update(slotRef, {
        waitlistCount: Math.max((slot.waitlistCount ?? 1) - 1, 0),
      });
      // registeredCount reste inchangé : une place confirmée en remplace
      // une autre.

      return {
        promoted: true as const,
        promotedUserId: nextInLine.data().userId as string,
        courseTitle: slot.courseTitle as string,
        slotDate: slot.date as admin.firestore.Timestamp,
        startTime: slot.startTime as string,
      };
    });

    // Envoi de la notification HORS de la transaction (jamais d'I/O externe
    // dans un `runTransaction`, qui peut être rejoué en cas de conflit).
    if (result.promoted) {
      const tokens = await getTokensForUids([result.promotedUserId], "waitlistPromoted");
      await sendPushToTokens(
        tokens,
        "Une place s'est libérée !",
        `Tu es inscrit.e ${registeredClause(result.courseTitle, result.slotDate, result.startTime)}.`
      );
    }

    return result;
  }
);

// ---------------------------------------------------------------------
// Rekovery — demandes de créneau (onglet dédié, remplace l'ancien système
// de sessions mêlées au planning). Cycle de vie complet : voir
// `rekovery_request_model.dart` côté Flutter (pending → accepted / proposed
// → accepted|cancelled / refused / cancelled).
// ---------------------------------------------------------------------

/**
 * Vrai si l'adhérent (formules du document `users/{uid}`) n'a QUE la
 * formule "Rekovery", sans formule sportive — c'est cet adhérent qui
 * dispose d'un carnet limité à 10 séances (`rekoveryCreditsRemaining`),
 * décompté uniquement à l'acceptation d'une demande (jamais à la simple
 * demande côté adhérent). Pendant serveur de `UserModel.isRekoverySoloOnly`
 * côté Flutter — la vérité côté crédit doit rester serveur, jamais confiée
 * au client.
 */
function isRekoverySoloOnly(formulas: string[] | undefined): boolean {
  const list = formulas ?? [];
  return list.length === 1 && list.includes("rekovery");
}

/**
 * Adhérent (formule "Rekovery") : crée une demande de créneau pour la
 * date/heure choisies. Ne vérifie/décompte PAS le carnet ici — seule
 * l'acceptation par un coach (ou d'une contre-proposition) décompte une
 * séance (voir [coachAcceptRekoveryRequest]/[respondToRekoveryProposal]).
 */
export const requestRekoverySlot = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");

    const { date, startTime } = request.data as { date?: string; startTime?: string };
    if (!date || !startTime) {
      throw new HttpsError("invalid-argument", "date et startTime requis.");
    }

    const userDoc = await db.collection("users").doc(uid).get();
    const userData = userDoc.data();
    if (!userDoc.exists || userData?.status !== "active") {
      throw new HttpsError("permission-denied", "Compte introuvable ou inactif.");
    }
    const formulas = (userData?.formulas as string[] | undefined) ?? [];
    if (!formulas.includes("rekovery")) {
      throw new HttpsError(
        "permission-denied",
        "La formule Rekovery n'est pas souscrite sur ce compte."
      );
    }

    const adherentName = `${userData?.firstName ?? ""} ${
      ((userData?.lastName as string | undefined) ?? "").charAt(0)
    }`.trim();

    const dateTimestamp = admin.firestore.Timestamp.fromDate(new Date(date));

    const reqRef = db.collection("rekoveryRequests").doc();
    await reqRef.set({
      adherentUid: uid,
      adherentName,
      date: dateTimestamp,
      startTime,
      status: "pending",
      proposedDate: null,
      proposedStartTime: null,
      coachNote: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const tokens = await getCoachTokens();
    // Titre/texte simplifiés (10 août 2026, demande de Margaux) — "à
    // [heure] le [date]" plutôt que "[date] à [heure]" : plus naturel en
    // français pour une date ("le 12/08", pas "à 12/08"). Jour de la
    // semaine ajouté le 18 août 2026 (demande de Margaux, voir
    // `weekdayShortDate`).
    await sendPushToTokens(
      tokens,
      "Nouvelle demande",
      `${adherentName} demande un Rekovery à ${startTime.replace(":", "h")} le ${weekdayShortDate(dateTimestamp)}.`
    );

    return { requestId: reqRef.id };
  }
);

/**
 * Coach : accepte une demande [pending] telle quelle (date/heure
 * inchangées). Pour un adhérent "Rekovery seul", décompte une séance du
 * carnet — échoue si le carnet est déjà à 0.
 */
export const coachAcceptRekoveryRequest = onCall(
  { region: REGION },
  async (request) => {
    await requireCoach(request.auth?.uid);

    const { requestId } = request.data as { requestId?: string };
    if (!requestId) throw new HttpsError("invalid-argument", "requestId requis.");

    const reqRef = db.collection("rekoveryRequests").doc(requestId);

    const result = await db.runTransaction(async (tx) => {
      const reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) throw new HttpsError("not-found", "Demande introuvable.");
      const reqData = reqSnap.data()!;
      if (reqData.status !== "pending") {
        throw new HttpsError("failed-precondition", "Cette demande n'est plus en attente.");
      }

      const userRef = db.collection("users").doc(reqData.adherentUid as string);
      const userSnap = await tx.get(userRef);
      const userData = userSnap.data();
      const formulas = (userData?.formulas as string[] | undefined) ?? [];

      if (isRekoverySoloOnly(formulas)) {
        const remaining = (userData?.rekoveryCreditsRemaining as number | undefined) ?? 0;
        if (remaining <= 0) {
          throw new HttpsError(
            "failed-precondition",
            "Le carnet Rekovery de cet adhérent est épuisé."
          );
        }
        tx.update(userRef, { rekoveryCreditsRemaining: remaining - 1 });
      }

      tx.update(reqRef, { status: "accepted" });

      return {
        adherentUid: reqData.adherentUid as string,
        date: reqData.date as admin.firestore.Timestamp,
        startTime: reqData.startTime as string,
      };
    });

    const tokens = await getTokensForUids([result.adherentUid], "rekoveryStatusChanged");
    // "Ton Rekovery du {jour} {JJ/MM} à {heure}..." (18 août 2026, demande
    // de Margaux — remplace "Ta séance Rekovery {JJ/MM} à {heure}...").
    // Accord au masculin ("confirmé", pas "confirmée") pour rester cohérent
    // avec "Ton" plutôt que "Ta séance".
    await sendPushToTokens(
      tokens,
      "Rekovery confirmé",
      `Ton Rekovery du ${weekdayShortDate(result.date)} à ${result.startTime.replace(":", "h")} est confirmé.`
    );

    return { ok: true };
  }
);

/**
 * Coach : refuse une demande [pending] ou [proposed] — aucun crédit
 * décompté. [note], si fourni, est affiché à l'adhérent (motif du refus).
 */
export const coachRefuseRekoveryRequest = onCall(
  { region: REGION },
  async (request) => {
    await requireCoach(request.auth?.uid);

    const { requestId, note } = request.data as { requestId?: string; note?: string };
    if (!requestId) throw new HttpsError("invalid-argument", "requestId requis.");

    const reqRef = db.collection("rekoveryRequests").doc(requestId);
    const reqSnap = await reqRef.get();
    if (!reqSnap.exists) throw new HttpsError("not-found", "Demande introuvable.");
    const reqData = reqSnap.data()!;
    if (reqData.status !== "pending" && reqData.status !== "proposed") {
      throw new HttpsError("failed-precondition", "Cette demande ne peut plus être refusée.");
    }

    await reqRef.update({ status: "refused", coachNote: note ?? null });

    const tokens = await getTokensForUids(
      [reqData.adherentUid as string],
      "rekoveryStatusChanged"
    );
    // Jour de la semaine ajouté le 18 août 2026 (demande de Margaux, voir
    // `weekdayShortDate`) — remplace la date seule (JJ/MM) de `formatDateAt`.
    const refusedWhen = `du ${weekdayShortDate(reqData.date)} à ${(reqData.startTime as string).replace(":", "h")}`;
    await sendPushToTokens(
      tokens,
      "Demande Rekovery refusée",
      note
        ? `Ta demande Rekovery ${refusedWhen} a été refusée : ${note}`
        : `Ta demande Rekovery ${refusedWhen} a été refusée.`
    );

    return { ok: true };
  }
);

/**
 * Coach : propose une autre date/heure plutôt que d'accepter/refuser
 * directement une demande [pending]. La demande passe à [proposed], en
 * attente de la réponse de l'adhérent (voir [respondToRekoveryProposal]).
 *
 * Pas de champ de message libre pour le coach ici (retiré le 6 août 2026,
 * voir `coach_rekovery_actions_sheet.dart`) — [coachNote] reste réservé au
 * motif de refus (voir [coachRefuseRekoveryRequest]) et n'est donc jamais
 * modifié par cette fonction.
 */
export const proposeRekoveryAlternative = onCall(
  { region: REGION },
  async (request) => {
    await requireCoach(request.auth?.uid);

    const { requestId, proposedDate, proposedStartTime } = request.data as {
      requestId?: string;
      proposedDate?: string;
      proposedStartTime?: string;
    };
    if (!requestId || !proposedDate || !proposedStartTime) {
      throw new HttpsError(
        "invalid-argument",
        "requestId, proposedDate et proposedStartTime requis."
      );
    }

    const reqRef = db.collection("rekoveryRequests").doc(requestId);
    const reqSnap = await reqRef.get();
    if (!reqSnap.exists) throw new HttpsError("not-found", "Demande introuvable.");
    const reqData = reqSnap.data()!;
    if (reqData.status !== "pending") {
      throw new HttpsError("failed-precondition", "Cette demande n'est plus en attente.");
    }

    const proposedTimestamp = admin.firestore.Timestamp.fromDate(new Date(proposedDate));
    await reqRef.update({
      status: "proposed",
      proposedDate: proposedTimestamp,
      proposedStartTime,
    });

    const tokens = await getTokensForUids(
      [reqData.adherentUid as string],
      "rekoveryStatusChanged"
    );
    // Jour de la semaine ajouté, "à la place" supprimé (18 août 2026,
    // demande de Margaux).
    await sendPushToTokens(
      tokens,
      "Rekovery : autre créneau proposé",
      `Le coach te propose le ${weekdayShortDate(proposedTimestamp)} à ${proposedStartTime.replace(":", "h")}.`
    );

    return { ok: true };
  }
);

/**
 * Adhérent : répond à une contre-proposition du coach ([proposed]).
 * [accept] à `true` confirme le créneau proposé (décompte le carnet, comme
 * une acceptation directe, sur la date/heure PROPOSÉES) ; à `false`, la
 * demande est annulée d'office — pas de nouvelle contre-proposition
 * possible.
 */
export const respondToRekoveryProposal = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");

    const { requestId, accept } = request.data as { requestId?: string; accept?: boolean };
    if (!requestId || typeof accept !== "boolean") {
      throw new HttpsError("invalid-argument", "requestId et accept requis.");
    }

    const reqRef = db.collection("rekoveryRequests").doc(requestId);

    const result = await db.runTransaction(async (tx) => {
      const reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) throw new HttpsError("not-found", "Demande introuvable.");
      const reqData = reqSnap.data()!;
      if (reqData.adherentUid !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Tu ne peux répondre qu'à tes propres demandes."
        );
      }
      if (reqData.status !== "proposed") {
        throw new HttpsError(
          "failed-precondition",
          "Cette demande n'a pas (ou plus) de contre-proposition en attente."
        );
      }

      if (!accept) {
        tx.update(reqRef, { status: "cancelled" });
        return { accepted: false as const };
      }

      const userRef = db.collection("users").doc(uid);
      const userSnap = await tx.get(userRef);
      const userData = userSnap.data();
      const formulas = (userData?.formulas as string[] | undefined) ?? [];

      if (isRekoverySoloOnly(formulas)) {
        const remaining = (userData?.rekoveryCreditsRemaining as number | undefined) ?? 0;
        if (remaining <= 0) {
          throw new HttpsError("failed-precondition", "Ton carnet Rekovery est épuisé.");
        }
        tx.update(userRef, { rekoveryCreditsRemaining: remaining - 1 });
      }

      tx.update(reqRef, {
        status: "accepted",
        date: reqData.proposedDate,
        startTime: reqData.proposedStartTime,
        proposedDate: null,
        proposedStartTime: null,
      });

      return {
        accepted: true as const,
        date: reqData.proposedDate as admin.firestore.Timestamp,
        startTime: reqData.proposedStartTime as string,
      };
    });

    if (result.accepted) {
      const tokens = await getCoachTokens();
      // Jour de la semaine ajouté le 18 août 2026 (demande de Margaux).
      await sendPushToTokens(
        tokens,
        "Rekovery confirmé",
        `La contre-proposition ${weekdayShortDate(result.date)} à ${result.startTime.replace(":", "h")} a été acceptée.`
      );
    }

    return { ok: true };
  }
);

/**
 * Adhérent (sa propre demande) ou coach (n'importe laquelle) : annule une
 * demande Rekovery, quel que soit son statut actuel (idempotent si déjà
 * [cancelled]/[refused]). Si elle était [accepted] (crédit déjà décompté),
 * le carnet de l'adhérent "Rekovery seul" est recrédité automatiquement.
 */
export const cancelRekoveryRequest = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");

    const { requestId } = request.data as { requestId?: string };
    if (!requestId) throw new HttpsError("invalid-argument", "requestId requis.");

    const reqRef = db.collection("rekoveryRequests").doc(requestId);

    await db.runTransaction(async (tx) => {
      const reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) throw new HttpsError("not-found", "Demande introuvable.");
      const reqData = reqSnap.data()!;

      const isOwner = reqData.adherentUid === uid;
      let isCoach = false;
      if (!isOwner) {
        const callerSnap = await tx.get(db.collection("users").doc(uid));
        const callerData = callerSnap.data();
        isCoach = callerData?.role === "coach" && callerData?.status === "active";
      }
      if (!isOwner && !isCoach) {
        throw new HttpsError(
          "permission-denied",
          "Tu ne peux annuler que tes propres demandes."
        );
      }
      if (reqData.status === "cancelled" || reqData.status === "refused") {
        return; // déjà dans un état final — rien à faire (idempotent).
      }

      // Une demande [accepted] avait décompté le carnet : on le recrédite
      // si l'adhérent est "Rekovery seul".
      if (reqData.status === "accepted") {
        const userRef = db.collection("users").doc(reqData.adherentUid as string);
        const userSnap = await tx.get(userRef);
        const userData = userSnap.data();
        const formulas = (userData?.formulas as string[] | undefined) ?? [];
        if (isRekoverySoloOnly(formulas)) {
          const remaining = (userData?.rekoveryCreditsRemaining as number | undefined) ?? 0;
          tx.update(userRef, { rekoveryCreditsRemaining: remaining + 1 });
        }
      }

      tx.update(reqRef, { status: "cancelled" });
    });

    return { ok: true };
  }
);

/**
 * Adhérent : modifie SA PROPRE demande (nouvelle date/heure) — action
 * "Modifier" du menu à appui long (demande du 6 août 2026, voir
 * `rekovery_request_actions_sheet.dart`). Autorisée quel que soit le statut
 * de départ, sauf [refused]/[cancelled] (états finaux). La demande repasse
 * systématiquement à [pending] : le coach doit de nouveau la valider,
 * exactement comme une toute nouvelle demande.
 *
 * Si la demande était [accepted] (crédit déjà décompté), le carnet de
 * l'adhérent "Rekovery seul" est recrédité automatiquement — même logique
 * que [cancelRekoveryRequest].
 */
export const modifyRekoveryRequest = onCall(
  { region: REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");

    const { requestId, date, startTime } = request.data as {
      requestId?: string;
      date?: string;
      startTime?: string;
    };
    if (!requestId || !date || !startTime) {
      throw new HttpsError("invalid-argument", "requestId, date et startTime requis.");
    }

    const reqRef = db.collection("rekoveryRequests").doc(requestId);

    const result = await db.runTransaction(async (tx) => {
      const reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) throw new HttpsError("not-found", "Demande introuvable.");
      const reqData = reqSnap.data()!;
      if (reqData.adherentUid !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Tu ne peux modifier que tes propres demandes."
        );
      }
      if (reqData.status === "cancelled" || reqData.status === "refused") {
        throw new HttpsError(
          "failed-precondition",
          "Cette demande n'est plus modifiable."
        );
      }

      // Une demande [accepted] avait décompté le carnet : on le recrédite
      // si l'adhérent est "Rekovery seul", puisqu'elle repasse en attente.
      if (reqData.status === "accepted") {
        const userRef = db.collection("users").doc(uid);
        const userSnap = await tx.get(userRef);
        const userData = userSnap.data();
        const formulas = (userData?.formulas as string[] | undefined) ?? [];
        if (isRekoverySoloOnly(formulas)) {
          const remaining = (userData?.rekoveryCreditsRemaining as number | undefined) ?? 0;
          tx.update(userRef, { rekoveryCreditsRemaining: remaining + 1 });
        }
      }

      const dateTimestamp = admin.firestore.Timestamp.fromDate(new Date(date));
      tx.update(reqRef, {
        status: "pending",
        date: dateTimestamp,
        startTime,
        proposedDate: null,
        proposedStartTime: null,
        coachNote: null,
      });

      return {
        adherentName: reqData.adherentName as string,
        date: dateTimestamp,
        startTime,
      };
    });

    const tokens = await getCoachTokens();
    // Jour de la semaine ajouté le 18 août 2026 (demande de Margaux).
    await sendPushToTokens(
      tokens,
      "Demande Rekovery modifiée",
      `${result.adherentName} a modifié sa demande : ${weekdayShortDate(result.date)} à ${result.startTime.replace(":", "h")}.`
    );

    return { ok: true };
  }
);

// ---------------------------------------------------------------------
// Notifications push — fonctions planifiées (vérifications périodiques)
// ---------------------------------------------------------------------

/**
 * Fenêtre large (avant/après aujourd'hui) utilisée pour pré-filtrer les
 * requêtes Firestore par plage sur `date` (index simple, déjà existant) —
 * le filtrage précis (heures exactes restantes, type, indicateurs déjà
 * envoyés...) se fait ensuite en mémoire sur ce petit lot de documents.
 */
function scanWindow(): { start: admin.firestore.Timestamp; end: admin.firestore.Timestamp } {
  const now = Date.now();
  return {
    start: admin.firestore.Timestamp.fromMillis(now - 24 * 60 * 60 * 1000),
    end: admin.firestore.Timestamp.fromMillis(now + 3 * 24 * 60 * 60 * 1000),
  };
}

/**
 * Section 1.3bis / 2.2ter : toutes les 15 minutes, repère les créneaux
 * collectifs/duo qui n'ont plus qu'un seul inscrit.
 *
 * Refonte du 18 août 2026 (demande de Margaux) — les 2 messages, jusque là
 * envoyés ENSEMBLE à un seul et même seuil (24h avant, 4h avant si lundi),
 * ont désormais chacun leur propre logique, avec leur propre indicateur
 * Firestore (fini `singleRegistrantAlertSent`, unique jusqu'ici) :
 * - "Tu es seul.e" (à l'unique inscrit(e)) : fenêtre FIXE de 24h, SANS
 *   exception le lundi (Margaux : "si une personne est ou devient seule
 *   dans les 24h qui précèdent sa séance, elle doit être prévenue
 *   instantanément") — un seul envoi (`soloAlertSent`).
 * - "Un binôme te cherche." (aux autres adhérents de la même formule) :
 *   DEUX envois désormais, un à 24h avant (texte inchangé,
 *   `binome24hAlertSent`) ET un autre à 4h avant, pour relancer une
 *   dernière fois avant que le cours ne soit compromis
 *   (`binome4hAlertSent`, texte légèrement différent — voir
 *   [courseDayPhrase]). Les deux envois sont indépendants l'un de l'autre.
 */
export const checkSingleRegistrantSlots = onSchedule(
  { schedule: "*/15 * * * *", region: REGION },
  async () => {
    const { start, end } = scanWindow();
    const snap = await db
      .collection("slots")
      .where("date", ">=", start)
      .where("date", "<=", end)
      .get();

    const now = Date.now();

    for (const doc of snap.docs) {
      const slot = doc.data();
      const formula = FORMULA_BY_SLOT_TYPE[slot.type as string];
      if (!formula) continue; // ni collectif ni duo
      if ((slot.registeredCount ?? 0) !== 1) continue;

      const needsSolo = !slot.soloAlertSent;
      const needsBinome24h = !slot.binome24hAlertSent;
      const needsBinome4h = !slot.binome4hAlertSent;
      if (!needsSolo && !needsBinome24h && !needsBinome4h) continue; // tout déjà envoyé

      const startInstant = slotStartInstant(slot.date, slot.startTime);
      const hoursUntilStart = (startInstant.getTime() - now) / (60 * 60 * 1000);
      if (hoursUntilStart <= 0) continue; // déjà commencé/passé
      if (hoursUntilStart > 24) continue; // trop tôt pour tout le monde

      try {
        const currentRegistrant = await db
          .collection("registrations")
          .where("slotId", "==", doc.id)
          .where("status", "==", "confirmed")
          .limit(1)
          .get();
        const excludeUids = currentRegistrant.docs.map((d) => d.data().userId as string);
        const updates: Record<string, boolean> = {};

        // "Tu es seul.e" : prévient l'unique inscrit(e) qu'il/elle risque de
        // se retrouver sans cours si personne ne le rejoint (26 juillet
        // 2026, demande de Margaux). Fenêtre fixe 24h depuis le 18 août
        // 2026 (plus d'exception le lundi).
        if (needsSolo) {
          if (excludeUids.length > 0) {
            const soloTokens = await getTokensForUids(excludeUids, "singleRegistrantAlert");
            await sendPushToTokens(
              soloTokens,
              "Tu es seul.e",
              `Tu es seul.e au ${slot.courseTitle} ${loneRegistrantClause(slot.date, slot.startTime)}.`
            );
          }
          updates.soloAlertSent = true;
        }

        // "Un binôme te cherche." : invitation aux autres adhérents de la
        // même formule à rejoindre le cours pour qu'il ne soit pas annulé —
        // envoyée à 24h (texte inchangé depuis le 17 août 2026) PUIS à
        // nouveau à 4h (texte avec [courseDayPhrase], plus adapté à
        // l'urgence proche — voir doc de fonction).
        if (needsBinome24h) {
          const tokens = await getTokensForFormula(formula, excludeUids, "singleRegistrantAlert");
          await sendPushToTokens(
            tokens,
            "Un binôme te cherche.",
            `Le cours ${slot.courseTitle} ${loneRegistrantClause(slot.date, slot.startTime)} n'a qu'un seul inscrit. Rejoins-le !`
          );
          updates.binome24hAlertSent = true;
        }
        if (needsBinome4h && hoursUntilStart <= 4) {
          const tokens = await getTokensForFormula(formula, excludeUids, "singleRegistrantAlert");
          await sendPushToTokens(
            tokens,
            "Un binôme te cherche.",
            `Le cours ${slot.courseTitle} ${courseDayPhrase(slot.date)} à ${formatTimeShort(slot.startTime)} n'a qu'un seul inscrit. Rejoins-le !`
          );
          updates.binome4hAlertSent = true;
        }

        if (Object.keys(updates).length > 0) {
          await doc.ref.update(updates);
        }
      } catch (err) {
        logger.error(`checkSingleRegistrantSlots: échec pour le créneau ${doc.id}`, err);
      }
    }
  }
);

/**
 * Section 1.3bis / 2.2ter (côté coach cette fois) : toutes les 15 minutes,
 * repère les créneaux collectifs/duo qui ont MOINS DE 2 inscrits (0 ou 1) et
 * dont le début approche dans moins de 4h, et alerte les coachs — pour
 * qu'ils puissent relancer ou décider d'une annulation avant qu'il ne soit
 * trop tard (17 août 2026, demande de Margaux : "les coachs doivent être
 * prévenus 4h avant quand un cours a moins de 2 inscrits"). Titre "Manque
 * de monde" (renommé le 18 août 2026, remplace "Créneau peu rempli"). Seuil
 * FIXE de 4h (pas d'exception le lundi ici, contrairement à
 * `checkSingleRegistrantSlots` qui vise les ADHÉRENTS) — indicateur dédié
 * (`coachLowRegistrationAlertSent`) pour ne se déclencher qu'une fois par
 * créneau, indépendant des indicateurs de `checkSingleRegistrantSlots`.
 */
export const checkLowRegistrationSlotsForCoach = onSchedule(
  { schedule: "*/15 * * * *", region: REGION },
  async () => {
    const { start, end } = scanWindow();
    const snap = await db
      .collection("slots")
      .where("date", ">=", start)
      .where("date", "<=", end)
      .get();

    const now = Date.now();

    for (const doc of snap.docs) {
      const slot = doc.data();
      if (!FORMULA_BY_SLOT_TYPE[slot.type as string]) continue; // ni collectif ni duo
      const registeredCount = slot.registeredCount ?? 0;
      if (registeredCount >= 2) continue;
      if (slot.coachLowRegistrationAlertSent) continue;

      const startInstant = slotStartInstant(slot.date, slot.startTime);
      const hoursUntilStart = (startInstant.getTime() - now) / (60 * 60 * 1000);
      if (hoursUntilStart <= 0) continue; // déjà commencé/passé
      if (hoursUntilStart > 4) continue; // pas encore dans la fenêtre des 4h

      try {
        const tokens = await getCoachTokens();
        const registrationClause =
          registeredCount === 0 ? "n'a personne d'inscrit" : "n'a qu'un seul inscrit";
        // Titre renommé "Manque de monde" le 18 août 2026 (demande de
        // Margaux — remplace "Créneau peu rempli").
        await sendPushToTokens(
          tokens,
          "Manque de monde",
          `Le cours ${slot.courseTitle} ${formatSlotWhen(slot.date, slot.startTime)} ${registrationClause}.`
        );
        await doc.ref.update({ coachLowRegistrationAlertSent: true });
      } catch (err) {
        logger.error(
          `checkLowRegistrationSlotsForCoach: échec pour le créneau ${doc.id}`,
          err
        );
      }
    }
  }
);

/**
 * Toutes les 15 minutes, rappelle 2h avant le début à chaque adhérent
 * inscrit (collectif/duo confirmés, ou individuel) qu'il a cours — pour
 * qu'il pense à y aller ou, s'il ne peut pas venir, à se désinscrire à
 * temps. N'envoie qu'une seule fois par créneau (`reminderSent`).
 */
export const sendCourseReminders = onSchedule(
  { schedule: "*/15 * * * *", region: REGION },
  async () => {
    const REMINDER_HOURS_BEFORE = 2;
    const { start, end } = scanWindow();
    const snap = await db
      .collection("slots")
      .where("date", ">=", start)
      .where("date", "<=", end)
      .get();

    const now = Date.now();

    for (const doc of snap.docs) {
      const slot = doc.data();
      if (!["collective", "duo", "individual"].includes(slot.type)) continue;
      if (slot.reminderSent) continue;

      const startInstant = slotStartInstant(slot.date, slot.startTime);
      const hoursUntilStart = (startInstant.getTime() - now) / (60 * 60 * 1000);
      if (hoursUntilStart <= 0 || hoursUntilStart > REMINDER_HOURS_BEFORE) continue;

      try {
        let recipientUids: string[];
        if (slot.type === "individual") {
          recipientUids = slot.adherentUid ? [slot.adherentUid as string] : [];
        } else {
          const regsSnap = await db
            .collection("registrations")
            .where("slotId", "==", doc.id)
            .where("status", "==", "confirmed")
            .get();
          recipientUids = regsSnap.docs.map((d) => d.data().userId as string);
        }
        if (recipientUids.length === 0) {
          await doc.ref.update({ reminderSent: true });
          continue;
        }

        const tokens = await getTokensForUids(recipientUids, "courseReminder");
        await sendPushToTokens(
          tokens,
          "Rappel de cours",
          `Tu es inscrit.e ${registeredClause(slot.courseTitle, slot.date, slot.startTime)}.`
        );
        await doc.ref.update({ reminderSent: true });
      } catch (err) {
        logger.error(`sendCourseReminders: échec pour le créneau ${doc.id}`, err);
      }
    }
  }
);

/**
 * Toutes les 10 minutes, rappelle aux coachs 1h avant une demande Rekovery
 * acceptée (60 min, remonté de 30 min le 10 août 2026 à la demande de
 * Margaux), pour qu'ils pensent à allumer le sauna avant l'arrivée de
 * l'adhérent. N'envoie qu'une seule fois par demande (`reminderSent`).
 */
export const sendRekoveryReminders = onSchedule(
  { schedule: "*/10 * * * *", region: REGION },
  async () => {
    const REMINDER_MINUTES_BEFORE = 60;
    const { start, end } = scanWindow();
    const snap = await db
      .collection("rekoveryRequests")
      .where("status", "==", "accepted")
      .where("date", ">=", start)
      .where("date", "<=", end)
      .get();

    const now = Date.now();

    for (const doc of snap.docs) {
      const req = doc.data();
      if (req.reminderSent) continue;

      const startInstant = slotStartInstant(req.date, req.startTime);
      const minutesUntilStart = (startInstant.getTime() - now) / (60 * 1000);
      if (minutesUntilStart <= 0 || minutesUntilStart > REMINDER_MINUTES_BEFORE) continue;

      try {
        const tokens = await getCoachTokens();
        // Titre/texte simplifiés (10 août 2026, demande de Margaux).
        await sendPushToTokens(tokens, "Rekovery", `${req.adherentName} arrive dans 1h.`);
        await doc.ref.update({ reminderSent: true });
      } catch (err) {
        logger.error(`sendRekoveryReminders: échec pour la demande ${doc.id}`, err);
      }
    }
  }
);

// ---------------------------------------------------------------------
// Notifications push — déclenchées par les écritures Firestore
// ---------------------------------------------------------------------

/** Compare les champs qu'un adhérent perçoit réellement (date/heure/titre) —
 * ignore les compteurs `registeredCount`/`waitlistCount`, qui changent à
 * chaque inscription/désinscription sans que le cours lui-même ait changé. */
function meaningfulSlotFieldsChanged(
  before: admin.firestore.DocumentData,
  after: admin.firestore.DocumentData
): boolean {
  const fields = ["date", "startTime", "endTime", "courseTitle", "description"];
  return fields.some((f) => {
    const b = before[f];
    const a = after[f];
    if (b instanceof admin.firestore.Timestamp && a instanceof admin.firestore.Timestamp) {
      return !b.isEqual(a);
    }
    return b !== a;
  });
}

/** Uid des adhérents concernés par un créneau duo/individuel : l'adhérent
 * poussé directement pour un individuel, ou tous les inscrits (confirmés et
 * en liste d'attente) pour un duo. */
async function affectedAdherentUids(slotId: string, slotData: admin.firestore.DocumentData): Promise<string[]> {
  if (slotData.type === "individual") {
    return slotData.adherentUid ? [slotData.adherentUid as string] : [];
  }
  const regsSnap = await db.collection("registrations").where("slotId", "==", slotId).get();
  return regsSnap.docs.map((d) => d.data().userId as string);
}

/**
 * Prévient un adhérent qui vient d'obtenir une inscription CONFIRMÉE (à
 * l'inscription directe si une place était libre, ou après une promotion
 * depuis la liste d'attente) s'il a déjà une autre inscription confirmée le
 * même jour calendaire — pour repérer une erreur de double inscription
 * avant de manquer l'un des deux cours. Les demandes Rekovery ne comptent
 * jamais : elles vivent dans une collection à part (`rekoveryRequests`),
 * jamais dans `registrations`.
 *
 * Un même jour calendaire correspond exactement à la même valeur du champ
 * `date` d'un créneau (toujours enregistrée sans heure, minuit local — voir
 * `SlotModel`/`groupSlotsByDay` côté client) : une simple égalité de
 * `Timestamp` suffit pour retrouver tous les créneaux du même jour, sans
 * avoir à gérer un fuseau horaire ici.
 */
async function checkSameDayDoubleBooking(
  registrationId: string,
  userId: string,
  slotId: string
): Promise<void> {
  const slotSnap = await db.collection("slots").doc(slotId).get();
  if (!slotSnap.exists) return;
  const slot = slotSnap.data()!;
  const slotDate = slot.date as admin.firestore.Timestamp;

  const daySlotsSnap = await db.collection("slots").where("date", "==", slotDate).get();
  if (daySlotsSnap.size <= 1) return; // seul ce créneau ce jour-là
  const sameDaySlotIds = new Set(daySlotsSnap.docs.map((d) => d.id));

  const regsSnap = await db
    .collection("registrations")
    .where("userId", "==", userId)
    .where("status", "==", "confirmed")
    .get();
  const otherSlotIds = new Set(
    regsSnap.docs
      .filter((d) => d.id !== registrationId && sameDaySlotIds.has(d.data().slotId))
      .map((d) => d.data().slotId as string)
  );
  if (otherSlotIds.size === 0) return;

  try {
    const tokens = await getTokensForUids([userId], "sameDayDoubleBooking");
    await sendPushToTokens(
      tokens,
      "Double inscription",
      `Tu es inscrit.e à ${otherSlotIds.size + 1} cours ${formatDayOnly(slotDate)}.`
    );
  } catch (err) {
    logger.error(`checkSameDayDoubleBooking: échec pour l'inscription ${registrationId}`, err);
  }
}

/** Inscription créée directement confirmée (place libre au moment de
 * l'inscription) → vérifie une éventuelle double inscription le même jour. */
export const onRegistrationCreated = onDocumentCreated(
  { document: "registrations/{registrationId}", region: REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data || data.status !== "confirmed") return;
    await checkSameDayDoubleBooking(event.params.registrationId, data.userId, data.slotId);
  }
);

/** Promotion depuis la liste d'attente (statut passant à "confirmed" après
 * coup, voir `cancelRegistration`) → même vérification. */
export const onRegistrationUpdated = onDocumentUpdated(
  { document: "registrations/{registrationId}", region: REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (before.status === "confirmed" || after.status !== "confirmed") return;
    await checkSameDayDoubleBooking(event.params.registrationId, after.userId, after.slotId);
  }
);

/**
 * Toutes les 15 minutes, en plus de l'alerte INSTANTANÉE de
 * [checkSameDayDoubleBooking] : rappelle une seconde fois, 24h avant le
 * PREMIER des cours de la journée concernée, à tout adhérent ayant plusieurs
 * inscriptions confirmées le même jour calendaire (18 août 2026, demande de
 * Margaux : "Double inscription doit poper instantanément ET 24h avant le
 * premier cours de la journée"). N'envoie qu'une seule fois par (adhérent,
 * jour) — indicateur `doubleBookingReminderSent` posé sur l'inscription du
 * PREMIER cours de ce jour-là pour cet adhérent (pas sur le jour en tant
 * que tel, qui n'a pas de document dédié).
 */
export const checkSameDayDoubleBookingReminders = onSchedule(
  { schedule: "*/15 * * * *", region: REGION },
  async () => {
    const { start, end } = scanWindow();
    const slotsSnap = await db
      .collection("slots")
      .where("date", ">=", start)
      .where("date", "<=", end)
      .get();
    if (slotsSnap.empty) return;

    // Regroupe les créneaux par jour calendaire exact (même principe que
    // [checkSameDayDoubleBooking] : le champ `date` est toujours minuit
    // local, donc une égalité de `Timestamp` suffit à identifier "le même
    // jour").
    const slotsByDay = new Map<number, admin.firestore.QueryDocumentSnapshot[]>();
    for (const doc of slotsSnap.docs) {
      const key = (doc.data().date as admin.firestore.Timestamp).toMillis();
      const list = slotsByDay.get(key) ?? [];
      list.push(doc);
      slotsByDay.set(key, list);
    }

    const now = Date.now();

    for (const daySlots of slotsByDay.values()) {
      if (daySlots.length < 2) continue; // un seul créneau ce jour-là : pas de double inscription possible
      const slotById = new Map(daySlots.map((d) => [d.id, d]));

      // Toutes les inscriptions CONFIRMÉES sur les créneaux de ce jour (par
      // lots de 30, limite Firestore de `documentId() in`/`in` — un seul
      // jour compte très largement moins de créneaux que ça en pratique).
      const regs: admin.firestore.QueryDocumentSnapshot[] = [];
      const slotIds = daySlots.map((d) => d.id);
      for (let i = 0; i < slotIds.length; i += 30) {
        const chunk = slotIds.slice(i, i + 30);
        const snap = await db
          .collection("registrations")
          .where("slotId", "in", chunk)
          .where("status", "==", "confirmed")
          .get();
        regs.push(...snap.docs);
      }

      const regsByUser = new Map<string, admin.firestore.QueryDocumentSnapshot[]>();
      for (const r of regs) {
        const uid = r.data().userId as string;
        const list = regsByUser.get(uid) ?? [];
        list.push(r);
        regsByUser.set(uid, list);
      }

      for (const [uid, userRegs] of regsByUser) {
        if (userRegs.length < 2) continue; // pas de double inscription pour cet adhérent ce jour-là

        // Le PREMIER cours de la journée pour cet adhérent (comparaison
        // lexicale de "HH:mm", valide car toujours sur 2 chiffres).
        let earliestReg = userRegs[0];
        let earliestSlot = slotById.get(userRegs[0].data().slotId as string)!;
        for (const r of userRegs.slice(1)) {
          const s = slotById.get(r.data().slotId as string)!;
          if ((s.data().startTime as string) < (earliestSlot.data().startTime as string)) {
            earliestReg = r;
            earliestSlot = s;
          }
        }
        if (earliestReg.data().doubleBookingReminderSent) continue;

        const startInstant = slotStartInstant(
          earliestSlot.data().date as admin.firestore.Timestamp,
          earliestSlot.data().startTime as string
        );
        const hoursUntilStart = (startInstant.getTime() - now) / (60 * 60 * 1000);
        if (hoursUntilStart <= 0 || hoursUntilStart > 24) continue;

        try {
          const tokens = await getTokensForUids([uid], "sameDayDoubleBooking");
          await sendPushToTokens(
            tokens,
            "Double inscription",
            `Tu es inscrit.e à ${userRegs.length} cours ${formatDayOnly(earliestSlot.data().date as admin.firestore.Timestamp)}.`
          );
          await earliestReg.ref.update({ doubleBookingReminderSent: true });
        } catch (err) {
          logger.error(`checkSameDayDoubleBookingReminders: échec pour ${uid}`, err);
        }
      }
    }
  }
);

/** Nouveau workshop : notifie tout le monde (coachs + adhérents actifs). */
export const onSlotCreated = onDocumentCreated(
  { document: "slots/{slotId}", region: REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data || data.type !== "workshop") return;
    try {
      const tokens = await getAllActiveTokens("workshopClosureBroadcast");
      await sendPushToTokens(
        tokens,
        "Nouveau workshop",
        `${data.courseTitle} ${formatSlotWhen(data.date, data.startTime)}.`
      );
    } catch (err) {
      logger.error(`onSlotCreated: échec pour ${event.params.slotId}`, err);
    }
  }
);

/**
 * Workshop modifié → notifie tout le monde. Cours duo/individuel modifié
 * (date/heure/titre réellement changés, pas juste une inscription en plus
 * ou en moins) → notifie les adhérents concernés.
 */
export const onSlotUpdated = onDocumentUpdated(
  { document: "slots/{slotId}", region: REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (!meaningfulSlotFieldsChanged(before, after)) return;

    try {
      if (after.type === "workshop") {
        const tokens = await getAllActiveTokens("workshopClosureBroadcast");
        await sendPushToTokens(
          tokens,
          "Workshop modifié",
          `${after.courseTitle} ${formatSlotWhen(after.date, after.startTime)}.`
        );
        return;
      }
      if (after.type === "duo" || after.type === "individual") {
        const uids = await affectedAdherentUids(event.params.slotId, after);
        const tokens = await getTokensForUids(uids, "duoIndividualChanged");
        // Refonte du 18 août 2026 (demande de Margaux) — "Ta séance" → "Ton
        // cours" (accord au masculin, "modifié" pas "modifiée"), jour de la
        // semaine ajouté à l'ancien créneau, ET précision du NOUVEAU
        // créneau (avant, seule l'ancienne date/heure était donnée — pas de
        // quoi savoir quand se replacer).
        const oldWhen = `${weekdayShortDate(before.date)} à ${(before.startTime as string).replace(":", "h")}`;
        const newWhen = `${weekdayFullDate(after.date)} à ${formatTimeShort(after.startTime)}`;
        await sendPushToTokens(
          tokens,
          "Ton cours a changé",
          `Ton cours ${after.courseTitle} du ${oldWhen} a été modifié. Nouveau créneau : ${newWhen}.`
        );
      }
    } catch (err) {
      logger.error(`onSlotUpdated: échec pour ${event.params.slotId}`, err);
    }
  }
);

/** Cours duo/individuel supprimé (suppression manuelle par un coach, ou
 * suppression automatique liée à une fermeture) → notifie les adhérents
 * concernés. */
export const onSlotDeleted = onDocumentDeleted(
  { document: "slots/{slotId}", region: REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    if (data.type !== "duo" && data.type !== "individual") return;

    try {
      const uids = await affectedAdherentUids(event.params.slotId, data);
      const tokens = await getTokensForUids(uids, "duoIndividualChanged");
      // "Ton cours" ajouté le 18 août 2026 (demande de Margaux).
      await sendPushToTokens(
        tokens,
        "Cours annulé",
        `Ton cours ${data.courseTitle} du ${formatSlotWhen(data.date, data.startTime)} a été annulé.`
      );
    } catch (err) {
      logger.error(`onSlotDeleted: échec pour ${event.params.slotId}`, err);
    }
  }
);

/** Nouvelle fermeture → notifie tout le monde. */
export const onClosureCreated = onDocumentCreated(
  { document: "closures/{closureId}", region: REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    try {
      const tokens = await getAllActiveTokens("workshopClosureBroadcast");
      await sendPushToTokens(
        tokens,
        "Fermeture de la salle",
        `Fermeture ${formatClosureWhen(data.startDate, data.endDate)}.`
      );
    } catch (err) {
      logger.error(`onClosureCreated: échec pour ${event.params.closureId}`, err);
    }
  }
);

/** Fermeture modifiée (dates et/ou message) → notifie tout le monde. */
export const onClosureUpdated = onDocumentUpdated(
  { document: "closures/{closureId}", region: REGION },
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return;
    try {
      const tokens = await getAllActiveTokens("workshopClosureBroadcast");
      await sendPushToTokens(
        tokens,
        "Fermeture modifiée",
        `Fermeture ${formatClosureWhen(after.startDate, after.endDate)}.`
      );
    } catch (err) {
      logger.error(`onClosureUpdated: échec pour ${event.params.closureId}`, err);
    }
  }
);