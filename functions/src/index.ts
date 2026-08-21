import { setGlobalOptions } from "firebase-functions/v2";

import { FUNCTION_REGION } from "./config";

setGlobalOptions({
  region: FUNCTION_REGION,
  maxInstances: 30,
  concurrency: 40
});

export {
  addComment,
  assignTicket,
  createTicket,
  escalateTicket,
  registerAttachment,
  transitionTicket,
  updateProductionImpact,
  updatePriority
} from "./commands";
export { checkOverdueTickets } from "./scheduler";
export { registerDevice, unregisterDevice } from "./devices";
export { onCommentCreated, onTicketCreated, onTicketUpdated } from "./triggers";
