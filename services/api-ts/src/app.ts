import formbody from "@fastify/formbody";
import multipart from "@fastify/multipart";
import Fastify, { type FastifyInstance } from "fastify";
import { healthResponseSchema } from "@voxlog/contracts";

import { config } from "./config.js";
import { pythonBackendClient, type BackendClient } from "./lib/backend-client.js";
import { registerDictionaryRoutes } from "./routes/dictionary.js";
import { registerDigestRoutes } from "./routes/digest.js";
import { registerHistoryRoutes } from "./routes/history.js";
import { registerRecentRoutes } from "./routes/recent.js";
import { registerSettingsRoutes } from "./routes/settings.js";
import { registerVoiceRoutes } from "./routes/voice.js";

export async function createApp(client: BackendClient = pythonBackendClient): Promise<FastifyInstance> {
  const app = Fastify({
    logger: true
  });

  await app.register(multipart);
  await app.register(formbody);

  app.get("/health", async () => {
    return healthResponseSchema.parse({
      status: "ok",
      service: "api-ts",
      python_backend_base_url: config.pythonBackendBaseUrl
    });
  });

  await registerRecentRoutes(app, client);
  await registerSettingsRoutes(app, client);
  await registerDictionaryRoutes(app, client);
  await registerDigestRoutes(app, client);
  await registerHistoryRoutes(app, client);
  await registerVoiceRoutes(app, client);

  return app;
}
