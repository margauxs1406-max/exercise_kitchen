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
 *  - generateWeeklySlots : génère chaque semaine les créneaux des cours
 *    collectifs récurrents (section 1.3 : "fixes d'une semaine à l'autre").
 *
 * Notifications push (FCM, section 4) : téléphone uniquement (pas
 * d'email/SMS), envoyées par les fonctions ci-dessous :
 *  - promotion liste d'attente → inscrit (dans `cancelRegistration`) ;
 *  - créneau collectif/duo à un seul inscrit, 24h avant (4h le lundi) —
 *    `checkSingleRegistrantSlots` ;
 *  - rappel de cours 2h avant à l'adhérent inscrit — `sendCourseReminders` ;
 *  - rappel Rekovery 30 min avant, aux coachs — `sendRekoveryReminders` ;
 *  - création/modification d'un workshop ou d'une fermeture, à tout le
 *    monde — `onSlotCreated`/`onSlotUpdated`/`onClosureCreated`/
 *    `onClosureUpdated` ;
 *  - modification/suppression d'un cours duo/individuel, aux adhérents
 *    concernés — `onSlotUpdated`/`onSlotDeleted` ;
 *  - double inscription le même jour (hors Rekovery), à l'adhérent
 *    concerné — `onRegistrationCreated`/`onRegistrationUpdated`.
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
const WEEK_DAYS = 7;

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
async function sendPushToTokens(
  tokens: string[],
  title: string,
  body: string
): Promise<void> {
  const unique = Array.from(new Set(tokens)).filter((t) => !!t);
  if (unique.length === 0) return;

  for (let i = 0; i < unique.length; i += 500) {
    const batch = unique.slice(i, i + 500);
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
      });
      response.responses.forEach((r, idx) => {
        if (!r.success) {
          logger.warn(`Échec d'envoi push pour un token`, {
            token: batch[idx],
            error: r.error?.message,
          });
        }
      });
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

/** Vrai si [date] correspond à un lundi une fois interprétée dans le fuseau
 * de Nouméa (nécessaire : le jour calendaire en UTC peut différer du jour
 * calendaire à Nouméa autour de minuit). */
function isMondayInNoumea(date: Date): boolean {
  const weekday = new Intl.DateTimeFormat("en-US", {
    timeZone: NOUMEA_TIME_ZONE,
    weekday: "short",
  }).format(date);
  return weekday === "Mon";
}

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

/** "20/07 à 18h00" — date courte + heure, sans le nom du jour (contrairement
 * à `formatSlotWhen`) — utilisé pour les messages de modification, où la
 * date précise reste utile mais pas le jour de la semaine. */
function formatDateAt(slotDate: admin.firestore.Timestamp, startTime: string): string {
  const dayMonth = new Intl.DateTimeFormat("fr-FR", {
    timeZone: NOUMEA_TIME_ZONE,
    day: "2-digit",
    month: "2-digit",
  }).format(slotDate.toDate());
  return `${dayMonth} à ${startTime.replace(":", "h")}`;
}

/** Clause "au Collectif de 12h" (jour même) ou "à Collectif lundi 20/07 à
 * 12h00" (autre jour), à insérer après "Tu es inscrit.e " dans les messages
 * de confirmation de place (nouvelle place directe, promotion liste
 * d'attente, rappel 2h avant) — la date complète est inutile quand le cours
 * a lieu aujourd'hui même (26/07/2026, demande de Margaux). */
function registeredClause(
  courseTitle: string,
  slotDate: admin.firestore.Timestamp,
  startTime: string
): string {
  if (isTodayInNoumea(slotDate.toDate())) {
    return `au ${courseTitle} de ${formatTimeShort(startTime)}`;
  }
  return `à ${courseTitle} ${formatSlotWhen(slotDate, startTime)}`;
}

/** "de demain 18h" ou "de 18h" (jour même, cas du lundi où l'alerte part 4h
 * avant plutôt que 24h) — utilisé dans le message envoyé à l'unique
 * inscrit(e) d'un créneau, voir `checkSingleRegistrantSlots`. */
function loneRegistrantClause(slotDate: admin.firestore.Timestamp, startTime: string): string {
  const timeShort = formatTimeShort(startTime);
  return isTodayInNoumea(slotDate.toDate()) ? `de ${timeShort}` : `de demain ${timeShort}`;
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

    const { firstName, lastName, email, phone, formulas } = request.data as {
      firstName?: string;
      lastName?: string;
      email?: string;
      phone?: string | null;
      formulas?: string[];
    };

    if (!firstName || !lastName || !email) {
      throw new HttpsError(
        "invalid-argument",
        "Prénom, nom et email sont requis."
      );
    }

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
    await sendPushToTokens(
      tokens,
      "Nouvelle demande Rekovery",
      `${adherentName} demande un créneau ${formatDateAt(dateTimestamp, startTime)}.`
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
    await sendPushToTokens(
      tokens,
      "Rekovery confirmé",
      `Ta séance Rekovery ${formatDateAt(result.date, result.startTime)} est confirmée.`
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
    await sendPushToTokens(
      tokens,
      "Demande Rekovery refusée",
      note
        ? `Ta demande Rekovery ${formatDateAt(reqData.date, reqData.startTime)} a été refusée : ${note}`
        : `Ta demande Rekovery ${formatDateAt(reqData.date, reqData.startTime)} a été refusée.`
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
    await sendPushToTokens(
      tokens,
      "Rekovery : autre créneau proposé",
      `Le coach te propose ${formatDateAt(proposedTimestamp, proposedStartTime)} à la place.`
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
      await sendPushToTokens(
        tokens,
        "Rekovery confirmé",
        `La contre-proposition ${formatDateAt(result.date, result.startTime)} a été acceptée.`
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
    await sendPushToTokens(
      tokens,
      "Demande Rekovery modifiée",
      `${result.adherentName} a modifié sa demande : ${formatDateAt(result.date, result.startTime)}.`
    );

    return { ok: true };
  }
);

/**
 * Génère, chaque lundi à 00h05 (heure de Nouméa), les créneaux de la semaine
 * à venir pour tous les cours collectifs récurrents (section 1.3 : créneaux
 * "fixes d'une semaine à l'autre"). Les cours duo ne sont pas concernés :
 * ils sont ajoutés ponctuellement par un coach via l'application.
 */
export const generateWeeklySlots = onSchedule(
  {
    schedule: "5 0 * * 1",
    timeZone: NOUMEA_TIME_ZONE,
    region: REGION,
  },
  async () => {
    const now = new Date();
    const monday = mondayOf(now);

    const coursesSnap = await db
      .collection("courses")
      .where("recurring", "==", true)
      .get();

    const batch = db.batch();
    let created = 0;

    for (const courseDoc of coursesSnap.docs) {
      const course = courseDoc.data();
      const dayOfWeek: number = course.recurringDayOfWeek ?? 1; // 1 = lundi
      const slotDate = new Date(monday);
      slotDate.setDate(monday.getDate() + (dayOfWeek - 1));

      // Évite les doublons si la fonction est relancée manuellement.
      const existing = await db
        .collection("slots")
        .where("courseId", "==", courseDoc.id)
        .where("date", "==", admin.firestore.Timestamp.fromDate(slotDate))
        .limit(1)
        .get();
      if (!existing.empty) continue;

      const slotRef = db.collection("slots").doc();
      batch.set(slotRef, {
        courseId: courseDoc.id,
        courseTitle: course.title,
        type: "collective",
        date: admin.firestore.Timestamp.fromDate(slotDate),
        startTime: course.startTime,
        endTime: course.endTime,
        capacity: course.capacity,
        registeredCount: 0,
        waitlistCount: 0,
      });
      created++;
    }

    await batch.commit();
    logger.info(`generateWeeklySlots : ${created} créneau(x) créé(s) pour la semaine du ${monday.toISOString()}`);
  }
);

function mondayOf(date: Date): Date {
  const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const day = d.getDay(); // 0 = dimanche
  const diff = day === 0 ? -6 : 1 - day;
  d.setDate(d.getDate() + diff + WEEK_DAYS); // semaine suivante
  return d;
}

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
 * collectifs/duo qui n'ont plus qu'un seul inscrit et dont le début approche
 * (24h avant ; 4h avant si le créneau tombe un lundi), et invite tous les
 * adhérents de la même formule (sauf l'unique inscrit actuel) à rejoindre le
 * cours, sans quoi il sera annulé. N'alerte qu'une seule fois par créneau
 * (`singleRegistrantAlertSent`).
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
      if (slot.singleRegistrantAlertSent) continue;

      const startInstant = slotStartInstant(slot.date, slot.startTime);
      const hoursUntilStart = (startInstant.getTime() - now) / (60 * 60 * 1000);
      if (hoursUntilStart <= 0) continue; // déjà commencé/passé

      const threshold = isMondayInNoumea(slot.date.toDate()) ? 4 : 24;
      if (hoursUntilStart > threshold) continue; // pas encore dans la fenêtre

      try {
        const currentRegistrant = await db
          .collection("registrations")
          .where("slotId", "==", doc.id)
          .where("status", "==", "confirmed")
          .limit(1)
          .get();
        const excludeUids = currentRegistrant.docs.map((d) => d.data().userId as string);

        // Message à l'unique inscrit(e) lui/elle-même : le prévient qu'il/elle
        // risque de se retrouver sans cours si personne ne le rejoint (26
        // juillet 2026, demande de Margaux — jusqu'ici seuls les AUTRES
        // adhérents étaient notifiés, jamais l'inscrit(e) lui/elle-même).
        if (excludeUids.length > 0) {
          const soloTokens = await getTokensForUids(excludeUids, "singleRegistrantAlert");
          await sendPushToTokens(
            soloTokens,
            "Tu es seul.e",
            `Tu es seul.e au ${slot.courseTitle} ${loneRegistrantClause(slot.date, slot.startTime)}.`
          );
        }

        // Message aux autres adhérents de la même formule : invitation à
        // rejoindre le cours pour qu'il ne soit pas annulé.
        const tokens = await getTokensForFormula(formula, excludeUids, "singleRegistrantAlert");
        await sendPushToTokens(
          tokens,
          "Un binôme te cherche.",
          `Le cours ${slot.courseTitle}, n'a qu'un seul inscrit. Rejoins-le!`
        );
        await doc.ref.update({ singleRegistrantAlertSent: true });
      } catch (err) {
        logger.error(`checkSingleRegistrantSlots: échec pour le créneau ${doc.id}`, err);
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
 * Toutes les 10 minutes, rappelle aux coachs 30 minutes avant une demande
 * Rekovery acceptée, pour qu'ils pensent à allumer le sauna avant l'arrivée
 * de l'adhérent. N'envoie qu'une seule fois par demande (`reminderSent`).
 */
export const sendRekoveryReminders = onSchedule(
  { schedule: "*/10 * * * *", region: REGION },
  async () => {
    const REMINDER_MINUTES_BEFORE = 30;
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
        await sendPushToTokens(
          tokens,
          "Rekovery dans 30 min",
          `${req.adherentName} arrive à ${(req.startTime as string).replace(":", "h")}. Allume le four !`
        );
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
        await sendPushToTokens(
          tokens,
          "Ton cours a changé",
          `Ta séance ${after.courseTitle} du ${formatDateAt(after.date, after.startTime)} a été modifiée.`
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
      await sendPushToTokens(
        tokens,
        "Cours annulé",
        `${data.courseTitle} du ${formatSlotWhen(data.date, data.startTime)} a été annulé.`
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