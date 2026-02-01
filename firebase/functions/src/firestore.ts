/**
 * Firestore helpers. Use FieldValue from firebase-admin/firestore;
 * admin.firestore.FieldValue is undefined in firebase-admin v12 (namespace only exposes Firestore class).
 */
import { FieldValue } from "firebase-admin/firestore";
export { FieldValue };
