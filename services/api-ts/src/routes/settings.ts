import type { FastifyInstance } from "fastify";
import {
  providerConnectivitySchema,
  providerSettingsSchema,
  providerSettingsUpdateSchema
} from "@voxlog/contracts";

import { pythonBackendClient, type BackendClient } from "../lib/backend-client.js";

export async function registerSettingsRoutes(
  app: FastifyInstance,
  client: BackendClient = pythonBackendClient
) {
  app.get("/v1/settings/providers", async () => {
    const json = await client.getJsonFromPython("/v1/settings/providers");
    return providerSettingsSchema.parse(json);
  });

  app.get("/v1/settings/providers/test", async () => {
    const json = await client.getJsonFromPython("/v1/settings/providers/test");
    return providerConnectivitySchema.parse(json);
  });

  app.post("/v1/settings/providers", async (request) => {
    const body = providerSettingsUpdateSchema.parse(request.body);
    const json = await client.postJsonToPython("/v1/settings/providers", body);
    return providerSettingsSchema.parse(json);
  });
}
