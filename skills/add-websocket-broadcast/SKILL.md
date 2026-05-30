---
name: add-websocket-broadcast
description: "Add a Quarkus websockets-next broadcast endpoint that fans out events to all connected clients via a single Mutiny BroadcastProcessor — generates the @WebSocket endpoint, a public notification method services can call, and a sample notification record. Use whenever the user asks for WebSocket notifications, server-push, real-time updates, broadcast to clients, or \"notify when X happens\"."
---

# add-websocket-broadcast

Add a `quarkus-websockets-next` endpoint that broadcasts notifications to all connected clients, matching this repo's `AlbumNotificationSocket` pattern.

## When to invoke

- "Add WebSocket notifications"
- "Notify clients when an album is created"
- "Push real-time updates"

## Inputs to collect

| Input | Default |
|---|---|
| Endpoint path | derived from event name, e.g. `/ws/<resource>` |
| Notification payload (record fields) | the entity's identifying fields |
| Trigger location | which service method calls the broadcaster |

## Dependency

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-websockets-next</artifactId>
</dependency>

<!-- Test client -->
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-websockets</artifactId>
    <scope>test</scope>
</dependency>
```

## File to generate — `websocket/<Event>NotificationSocket.java`

For an `Album` resource with a `notifyNewAlbum` trigger:

```java
package {{packageRoot}}.websocket;

import {{packageRoot}}.entity.Album;
import io.quarkus.logging.Log;
import io.quarkus.websockets.next.OnClose;
import io.quarkus.websockets.next.OnOpen;
import io.quarkus.websockets.next.WebSocket;
import io.quarkus.websockets.next.WebSocketConnection;
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.operators.multi.processors.BroadcastProcessor;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

@WebSocket(path = "/ws/albums")
@ApplicationScoped
public class AlbumNotificationSocket {

    @Inject WebSocketConnection connection;

    /** Static so every CDI proxy of this bean shares the same broadcast stream. */
    private static final BroadcastProcessor<AlbumNotification> broadcaster = BroadcastProcessor.create();

    public record AlbumNotification(Long id, String title, Integer year) {}

    @OnOpen
    public Multi<AlbumNotification> onOpen() {
        Log.infof("Client connected: %s", connection.id());
        return broadcaster;
    }

    @OnClose
    public void onClose() {
        Log.infof("Client disconnected: %s", connection.id());
    }

    public void notifyNewAlbum(Album album) {
        broadcaster.onNext(new AlbumNotification(album.getId(), album.getTitle(), album.getYear()));
    }
}
```

> **Why static**: the `BroadcastProcessor` must be shared across every CDI lookup of the bean. In `@ApplicationScoped` this is technically already a singleton, but using a `static` field makes the intent explicit and survives any future change in scope.

## Trigger integration

In the relevant service (e.g. `AlbumService`), inject the socket and call `notifyNewAlbum(album)` **after** the persist succeeds:

```java
@Inject AlbumNotificationSocket notificationSocket;

// inside create(...)
albumRepository.persist(album);
notificationSocket.notifyNewAlbum(album);
```

If `create` is `@Transactional`, the notification fires while the transaction is still open. For a stronger guarantee that consumers only see committed data, hook into a CDI lifecycle event or use a transaction synchronization observer. This is rarely necessary for a notification-style broadcast; only mention it to the user if they call out at-least-once semantics.

## Test pattern

```java
package {{packageRoot}}.websocket;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.websockets.next.WebSocketClientConnection;
import io.quarkus.websockets.next.WebSocketConnector;
import jakarta.inject.Inject;
import org.junit.jupiter.api.Test;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertNotNull;

@QuarkusTest
class AlbumNotificationSocketTest {

    @Inject AlbumNotificationSocket socket;
    @Inject WebSocketConnector<AlbumNotificationSocket> connector;

    @Test
    void broadcastsToConnectedClients() throws Exception {
        CompletableFuture<String> received = new CompletableFuture<>();
        WebSocketClientConnection client = connector.connectAndAwait();
        client.onTextMessage((c, m) -> { received.complete(m); return null; });

        // simulate the service calling the broadcaster
        socket.notifyNewAlbum(/* construct sample Album */);

        assertNotNull(received.get(2, TimeUnit.SECONDS));
    }
}
```

> Adjust to the actual `Album` constructor available. If the entity has many required fields, prefer creating a small test factory rather than inflating the test.

## Anti-patterns to refuse

- Sending huge payloads through the broadcaster. Push **identifiers + metadata**, let clients fetch details via REST. This keeps WebSocket frames small and avoids serializing entity graphs.
- Coupling the broadcaster to the entity directly — the `record AlbumNotification(...)` is the contract; entity changes shouldn't break wire format.
- Trying to use this for back-and-forth conversation. `BroadcastProcessor` is fan-out only. For request/response semantics, use `@OnTextMessage` with a different design.
- Calling `notifyNewAlbum` before `persist()` returns. Order matters: persist first, then notify, so subscribers can immediately query the new resource if they want.

## Post-generation

- Tell the user the WebSocket URL: `ws://localhost:8080/ws/<resource>`.
- Provide a one-liner JS snippet for manual testing:
  ```javascript
  new WebSocket('ws://localhost:8080/ws/albums').onmessage = e => console.log(JSON.parse(e.data));
  ```

---

## Strategic considerations & governance

## Goal

Verify realtime behavior without flaky timing assumptions.

## Workflow

1. Define connection URL, authentication behavior, subscription model, and expected message schema.
2. Establish the WebSocket connection and wait for an explicit connected or subscribed signal when available.
3. Trigger the server event through the normal API or service path.
4. Await expected messages with bounded timeouts and clear failure output.
5. Assert message type, payload fields, ordering requirements, and absence of unexpected messages.
6. Test disconnect, reconnect, unauthorized connection, and malformed message paths when supported.

## Stability Rules

- Do not use fixed sleeps as synchronization.
- Subscribe before triggering the event.
- Use unique test data so messages cannot be confused with other tests.
- Close clients and sessions after each test.
- Keep timeout values bounded and documented.

## Example

For album notifications, connect a test client, wait until subscribed, create an album through `AlbumResource`, then assert one message with the new album ID, title, and event type.
