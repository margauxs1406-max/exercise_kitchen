// migrate_delete_ghost_18h_slots.js
//
// Script PONCTUEL, à exécuter UNE SEULE FOIS pour supprimer définitivement
// les créneaux collectifs fantômes du lundi/vendredi 18h-19h (capacité 12)
// signalés par Margaux à plusieurs reprises (23 juillet puis 7 août 2026).
//
// Pourquoi ces créneaux ne sont PAS générés par le code actuel : le planning
// fixe des cours collectifs (`lib/data/default_collective_schedule.dart`,
// `kDefaultCollectiveSchedule`) ne contient AUCUN créneau à 18h, et la
// capacité par défaut y est 8 (`kDefaultCollectiveCapacity`), pas 12. Ces
// documents "18h, capacité 12" sont donc des RESTES d'une ancienne version
// du planning (avant que ces horaires soient retirés), créés en masse à
// l'époque par `ensureCollectiveSlotsAhead` (qui matérialise plusieurs
// semaines à l'avance à chaque ouverture du planning coach) — il en existe
// donc très probablement plusieurs dizaines, pour de nombreuses semaines
// PASSÉES ET FUTURES, pas seulement celles déjà remarquées et supprimées à
// la main dans la console Firebase. C'est cette réserve de documents déjà
// existants, mais pas encore tous découverts, qui donnait l'impression que
// de nouveaux créneaux "se régénéraient" chaque semaine : rien ne les
// recréait, ils étaient déjà tous là depuis longtemps, et n'apparaissaient
// dans le planning qu'au fil de l'avancée du calendrier.
//
// Ce que fait ce script : supprime TOUS les documents de la collection
// `slots` où `type == "collective"` ET `startTime == "18:00"`, quelle que
// soit leur date (passée ou future) — un nettoyage complet et définitif,
// plutôt que de continuer à les supprimer un par un à chaque fois qu'une
// nouvelle semaine les révèle. Comme le code actuel ne génère plus jamais ce
// créneau, aucun risque qu'ils réapparaissent après cette suppression.
//
// Utilisation (Windows PowerShell, depuis le dossier functions/) :
//   1. Réutiliser la clé de compte de service des scripts précédents, ou en
//      générer une nouvelle : Console Firebase > Paramètres du projet >
//      Comptes de service > "Générer une nouvelle clé privée".
//   2. Dans PowerShell, depuis functions/ :
//        $env:GOOGLE_APPLICATION_CREDENTIALS="C:\chemin\vers\la-cle.json"
//        node migrate_delete_ghost_18h_slots.js
//   3. Vérifier le résumé affiché dans la console ("X créneau(x) fantôme(s)
//      supprimé(s)").
//   4. Supprimer ce fichier ET la clé .json téléchargée une fois exécuté.

const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

async function main() {
  const snap = await db
    .collection("slots")
    .where("type", "==", "collective")
    .where("startTime", "==", "18:00")
    .get();

  if (snap.empty) {
    console.log("Aucun créneau fantôme à 18h trouvé — rien à faire.");
    return;
  }

  console.log(`${snap.size} créneau(x) fantôme(s) trouvé(s), suppression en cours...`);

  // Un `WriteBatch` Firestore est limité à 500 opérations : on découpe au
  // besoin, même si le nombre réel de documents concernés devrait rester
  // largement en dessous de cette limite pour une seule salle.
  const docs = snap.docs;
  for (let i = 0; i < docs.length; i += 500) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + 500)) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  console.log(`Terminé : ${docs.length} créneau(x) fantôme(s) supprimé(s).`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Erreur pendant la suppression :", err);
    process.exit(1);
  });
