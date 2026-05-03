---
name: rgd-authoring
description: Write ResourceGraphDefinitions for kro. Use when creating RGDs, defining schemas, writing CEL expressions, or configuring resources.
allowed-tools: Read, Grep, Glob
---

This is the all-in-one documentation for kro-codile: a dangerously wild, ahead-of-time version of kro with custom features that have not been released yet. Use this file as the source of truth for authoring against `kro-codile`, not just upstream kro.

# Workflow

When this skill is invoked:

1. **Determine what the user needs**:
   - RGD only → output the ResourceGraphDefinition
   - Instance only → find the existing RGD, then output a matching instance
   - Both → output both the RGD and an example instance
   - Unclear → ask the user which they need

2. **Gather requirements**:
   - For RGDs: the user must specify what resources to orchestrate. If not provided, ask.
   - For instances: search for the target RGD in the codebase to understand its schema.

3. **Output**: Present YAML in code blocks. Keep explanations brief and focused on non-obvious choices.

# RGD Authoring Reference

One annotated example covering all features.

```yaml
apiVersion: kro.run/v1alpha1
kind: ResourceGraphDefinition
metadata:
  name: web-platform
  annotations:
    # BREAKING CHANGES
    # By default kro blocks breaking schema updates (field removal, type changes,
    # new required fields without defaults, enum restrictions, pattern changes).
    # Set this annotation to allow them:
    kro.run/allow-breaking-changes: "true"
spec:
  schema:
    # API IDENTIFICATION
    # These define the GVK for the generated CRD. All three are immutable.
    apiVersion: v1alpha1                    # Required. Pattern: v[0-9]+(alpha|beta)?[0-9]*
    kind: WebPlatform                       # Required. PascalCase, max 63 chars
    group: mycompany.io                     # Optional. Defaults to "kro.run"

    # CRD METADATA
    # Labels and annotations applied to the generated CRD itself (not instances).
    metadata:
      labels:
        team: platform
        managed-by: kro
      annotations:
        description: "Web platform resource"

    # CUSTOM TYPES
    # Reusable type definitions. Reference in spec using the type name.
    types:
      DatabaseSpec:
        name: string | required=true
        storage: string | default="10Gi"
        backupEnabled: boolean | default=true

    # SPEC - User inputs
    # SimpleSchema syntax: type | marker=value marker2=value2
    spec:
      # Basic types with validation markers
      name: string | required=true immutable=true description="Application name"
      image: string | required=true
      replicas: integer | default=3 minimum=1 maximum=100

      # String validation
      email: string | pattern="^[\\w.-]+@[\\w.-]+\\.\\w+$"
      username: string | minLength=3 maxLength=20

      # Enum - allowed values
      environment: string | enum="dev,staging,prod" default="dev"

      # Nested object - defaults to {} if not provided by user
      ingress:
        enabled: boolean | default=false
        host: string
        path: string | default="/"
        tls: boolean | default=false

      # Array types - quote complex types
      ports: "[]integer | default=[80]"
      tags: "[]string | uniqueItems=true minItems=1 maxItems=10"

      # Map types
      labels: "map[string]string"
      env: "map[string]string"

      # Custom type reference (defined above in types)
      databases: "[]DatabaseSpec"

      # Unstructured object - use sparingly, disables validation
      extraConfig: object

    # STATUS - Computed from resources via CEL expressions
    # Types are inferred from the expression return type.
    status:
      # Single expression - can be any type
      availableReplicas: ${deployment.status.availableReplicas}
      ready: ${deployment.status.availableReplicas >= schema.spec.replicas}

      # String template - multiple expressions, all must return strings
      endpoint: "https://${service.metadata.name}.${service.metadata.namespace}.svc"

      # Use string() to convert non-strings in templates
      summary: "Replicas: ${string(deployment.status.replicas)}"

      # Aggregating from collections
      databaseCount: ${size(databases)}
      allDatabasesReady: ${databases.all(db, db.status.?phase == "Ready")}

      # Structured status object
      connection:
        host: ${service.spec.clusterIP}
        port: ${service.spec.ports[0].port}

      # Status array with individual elements
      endpoints:
        - ${service.status.loadBalancer.ingress[0].hostname}
        - ${service.status.loadBalancer.ingress[1].hostname}

      # Status array from multiple resources
      databaseEndpoints:
        - ${database1.status.endpoint}
        - ${database2.status.endpoint}

    # PRINTER COLUMNS - Custom kubectl get output
    additionalPrinterColumns:
      - name: Replicas
        type: integer
        jsonPath: .spec.replicas
      - name: Available
        type: integer
        jsonPath: .status.availableReplicas
      - name: Age
        type: date
        jsonPath: .metadata.creationTimestamp

  # RESOURCES
  # Each resource needs: id (lowerCamelCase) + template OR externalRef
  # Recommended field order: id, forEach, readyWhen, includeWhen, template/externalRef
  resources:

    # EXTERNAL REFERENCE
    # Reads existing resource, never creates/updates/deletes it.
    # externalRef.metadata uses `name` for scalar refs or `selector` for selector-based collections.
    # `forEach` can also be combined with scalar externalRef lookups to build a collection.
    # readyWhen and includeWhen CAN be used with externalRef.
    - id: platformConfig
      readyWhen:
        - ${platformConfig.data.?ready == "true"}
      includeWhen:
        - ${schema.spec.usePlatformConfig}
      externalRef:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: platform-config
          namespace: platform-system       # Optional, defaults to instance namespace

    # EXTERNAL REFERENCE COLLECTION (by label selector)
    # Fetches multiple existing resources as an array. name and selector are mutually exclusive.
    - id: teamConfigs
      externalRef:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          selector:
            matchLabels:
              team: platform
            # Set-based expressions also supported
            matchExpressions:
              - key: tier
                operator: In
                values: ["gold", "silver"]

    # EXTERNAL COLLECTION WITH CEL IN SELECTOR
    - id: envConfigs
      externalRef:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          selector:
            matchExpressions:
              - key: team
                operator: In
                values: ["${schema.spec.teamName}"]

    # Sorting external collections: ${teamConfigs.sortBy(c, c.metadata.name)}
    # Empty selector (selector: {}) matches ALL resources of that kind — use with caution.

    # EXTERNAL COLLECTION WITH forEach
    # Fan out many explicit names into one read-only collection.
    - id: databaseConfigs
      forEach:
        - refName: ${schema.spec.databases.map(db, db.name)}
      readyWhen:
        - ${each.data.?ready == "true"}
      externalRef:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: ${refName}

    # BASIC RESOURCE WITH CEL EXPRESSIONS
    # ${...} wraps CEL. References create implicit dependencies.
    - id: deployment
      readyWhen:
        - ${deployment.status.availableReplicas > 0}
        - ${deployment.status.conditions.exists(c, c.type == "Available" && c.status == "True")}
      template:
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: ${schema.spec.name}
          namespace: ${schema.metadata.namespace}
          labels: ${schema.spec.labels}
        spec:
          replicas: ${schema.spec.replicas}
          selector:
            matchLabels:
              app: ${schema.spec.name}
          template:
            metadata:
              labels:
                app: ${schema.spec.name}
            spec:
              containers:
                - name: app
                  image: ${schema.spec.image}
                  ports:
                    - containerPort: ${schema.spec.ports[0]}
                  env:
                    # Reference external resource with ? for untyped fields
                    - name: PLATFORM_URL
                      value: ${platformConfig.data.?platformUrl.orValue("http://default")}
                    # Ternary conditional
                    - name: LOG_LEVEL
                      value: ${schema.spec.environment == "prod" ? "warn" : "debug"}
                  # SHELL VARIABLE ESCAPING
                  # Use ${"${VAR}"} to produce literal ${VAR} in output (e.g. container commands)
                  command:
                    - bash
                    - -c
                    - echo "Hello ${"${USER}"} from ${schema.spec.name}"

    # RESOURCE WITH REFERENCE TO OTHER RESOURCE
    # Creates dependency: service waits for deployment
    - id: service
      template:
        apiVersion: v1
        kind: Service
        metadata:
          name: ${schema.spec.name}
        spec:
          selector:
            app: ${deployment.spec.template.metadata.labels.app}
          ports:
            - port: 80
              targetPort: ${schema.spec.ports[0]}

    # CONDITIONAL RESOURCE
    # includeWhen: all conditions must be true. Can reference schema.spec and upstream resources.
    # If false, resource AND all its dependents are skipped.
    - id: ingress
      includeWhen:
        - ${schema.spec.ingress.enabled}
      template:
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: ${schema.spec.name}
        spec:
          rules:
            - host: ${schema.spec.ingress.host}
              http:
                paths:
                  - path: ${schema.spec.ingress.path}
                    pathType: Prefix
                    backend:
                      service:
                        name: ${service.metadata.name}
                        port:
                          number: 80

    # CONDITIONAL WITH MULTIPLE CONDITIONS (AND logic)
    - id: certificate
      includeWhen:
        - ${schema.spec.ingress.enabled}
        - ${schema.spec.ingress.tls}
      template:
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: ${schema.spec.name}-tls
        spec:
          secretName: ${schema.spec.name}-tls
          dnsNames:
            - ${schema.spec.ingress.host}

    # STATUS-BACKED CONDITIONAL
    # Resource-backed includeWhen participates in dependency inference and cycle detection.
    # kro keeps reconciliation pending until referenced resources are observed and ready.
    - id: rolloutReport
      includeWhen:
        - ${deployment.status.availableReplicas == schema.spec.replicas}
      template:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: ${schema.spec.name}-rollout-report
        data:
          status: stable

    # COLLECTION (forEach)
    # Creates multiple resources from single definition.
    # `forEach` works with templates and scalar externalRef lookups.
    # Iterator variable available in template.
    - id: databases
      forEach:
        - dbSpec: ${schema.spec.databases}
      # readyWhen in collections uses `each` keyword (not the resource id)
      readyWhen:
        - ${each.status.?phase == "Ready"}
      template:
        apiVersion: database.example.com/v1
        kind: PostgreSQL
        metadata:
          # MUST include iterator variable for unique names
          name: ${schema.metadata.name}-${dbSpec.name}
        spec:
          storage: ${dbSpec.storage}

    # COLLECTION WITH FILTER
    # Use filter() to exclude items (includeWhen is all-or-nothing for collections)
    - id: backupJobs
      forEach:
        - dbSpec: ${schema.spec.databases.filter(d, d.backupEnabled)}
      template:
        apiVersion: batch/v1
        kind: CronJob
        metadata:
          name: ${schema.metadata.name}-backup-${dbSpec.name}
        spec:
          schedule: "0 2 * * *"
          jobTemplate:
            spec:
              template:
                spec:
                  containers:
                    - name: backup
                      image: backup-tool:latest

    # CARTESIAN PRODUCT (multiple iterators)
    # regions × tiers = creates resource for each combination
    - id: regionalConfigs
      forEach:
        - region: ${["us-east", "us-west", "eu-west"]}
        - tier: ${["web", "api"]}
      template:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          # Creates: myapp-us-east-web, myapp-us-east-api, myapp-us-west-web, ...
          name: ${schema.metadata.name}-${region}-${tier}
        data:
          region: ${region}
          tier: ${tier}

    # REFERENCING A COLLECTION
    # Collection exposed as array. Use CEL functions to aggregate.
    - id: summary
      template:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: ${schema.metadata.name}-summary
        data:
          databaseNames: ${databases.map(db, db.metadata.name).join(",")}
          totalDatabases: ${string(size(databases))}
          allReady: ${string(databases.all(db, db.status.?phase == "Ready"))}

    # ITERATE USING INDEX
    # Use lists.range() to get indices
    - id: indexedPods
      forEach:
        - idx: ${lists.range(schema.spec.replicas)}
      # MULTILINE EXPRESSIONS
      # Use YAML block scalars (|- or >-) with chomp indicator for complex CEL
      readyWhen:
        - |-
          ${
            each.status.?phase == "Running" &&
            each.status.?conditions.exists(c, c.type == "Ready" && c.status == "True")
          }
      template:
        apiVersion: v1
        kind: Pod
        metadata:
          name: ${schema.metadata.name}-worker-${string(idx)}
        spec:
          containers:
            - name: worker
              image: ${schema.spec.image}
              env:
                - name: WORKER_INDEX
                  value: ${string(idx)}
```

### Collection Lifecycle

- **Scaling up**: adding items to the iterator array creates new resources automatically
- **Scaling down**: removing items deletes the corresponding resources
- **Empty collections** (`[]`): zero resources created, collection is considered ready
- **Cartesian with empty**: if any iterator in a cartesian product is empty, zero resources created
- **Drift detection**: kro automatically restores drifted collection resources to desired state

## Instance Example

Once the RGD above is applied, kro generates a CRD. Users then create instances:

```yaml
apiVersion: mycompany.io/v1alpha1
kind: WebPlatform
metadata:
  name: my-app
  namespace: production
spec:
  # Required fields
  name: my-app
  image: nginx:1.25

  # Optional with defaults (can omit)
  replicas: 5 # default: 3
  environment: prod # default: dev

  # String validation
  email: admin@mycompany.io
  username: appuser

  # Nested object
  ingress:
    enabled: true
    host: my-app.mycompany.io
    tls: true
    # path defaults to "/"

  # Arrays
  ports:
    - 80
    - 443
  tags:
    - production
    - critical

  # Maps
  labels:
    team: platform
    cost-center: engineering
  env:
    LOG_FORMAT: json
    METRICS_PORT: "9090"

  # Custom type array
  databases:
    - name: primary
      storage: 50Gi
      backupEnabled: true
    - name: analytics
      storage: 100Gi
      backupEnabled: false

  # Unstructured (any valid YAML)
  extraConfig:
    customSetting: value
    nested:
      anything: goes
```

The resulting status (populated by kro from resource states):

```yaml
status:
  availableReplicas: 5
  ready: true
  endpoint: https://my-app.production.svc
  summary: "Replicas: 5"
  databaseCount: 2
  allDatabasesReady: true
  connection:
    host: 10.96.45.123
    port: 80
  databaseEndpoints:
    - primary.mycompany.io:5432
    - analytics.mycompany.io:5432
```

## Available CEL Libraries

| Library | Source | Examples |
| ------- | ------ | -------- |
| Lists | cel-go/ext | `lists.range()`, `lists.flatten()` |
| Strings | cel-go/ext | `.split()`, `.join()`, `.trim()`, `.replace()`, `.lowerAscii()`, `.upperAscii()` |
| Encoders | cel-go/ext | `base64.encode()`, `base64.decode()` |
| Random | kro custom | `random.string()`, `random.integer()` |
| JSON | kro custom | `json.marshal()`, `json.unmarshal()` |
| URLs | k8s apiserver | `url()`, `.getScheme()`, `.getHost()`, `.getPath()` |
| Regex | k8s apiserver | `.matches()`, `.find()`, `.findAll()` |

## Quick Reference

| Feature                | Syntax                                      | Scope                                            |
| ---------------------- | ------------------------------------------- | ------------------------------------------------ |
| CEL expression         | `${expression}`                             | Any field value                                  |
| String template        | `"prefix-${expr}-suffix"`                   | String fields only, all exprs must return string |
| Reference schema       | `${schema.spec.fieldName}`                  | Instance spec values                             |
| Reference metadata     | `${schema.metadata.name}`                   | Instance name/namespace/labels/annotations       |
| Reference resource     | `${resourceId.spec.field}`                  | Creates dependency                               |
| Optional field         | `${resource.field.?maybeField}`             | Returns null if missing                          |
| Default value          | `${resource.data.?key.orValue("default")}`  | Fallback for optional                            |
| Conditional            | `${condition ? valueIfTrue : valueIfFalse}` | Ternary                                          |
| includeWhen            | Can reference `schema.spec` + upstream resources | All conditions AND; waits for upstream data as needed |
| readyWhen (resource)   | Can only reference self by id               | All conditions AND                               |
| readyWhen (collection) | Uses `each` keyword                         | Per-item check, including collection externalRefs |
| forEach                | `- varName: ${arrayExpression}`             | Variable available in template or scalar externalRef |
| Multiline expr         | `\|- \n  ${ ... }`                          | YAML block scalar with chomp indicator           |
| Shell var escape       | `${"${VAR}"}`                               | Produces literal `${VAR}` in output              |
| externalRef collection | `selector: { matchLabels: ... }`            | Fetches multiple resources as array              |
| externalRef + forEach  | `forEach` + `metadata.name: ${refName}`     | Fetches many explicit refs as one array          |
| Sort collection        | `${coll.sortBy(c, c.field)}`               | Orders external collection results               |
| Breaking changes       | `kro.run/allow-breaking-changes: "true"`    | RGD annotation to allow breaking updates         |
| CRD metadata           | `schema.metadata.labels/annotations`        | Applied to generated CRD, not instances          |

## Key Rules

### Naming Constraints

- Resource `id` must be lowerCamelCase (e.g., `deployment`, `webServer`, `postgresDb`)
- Resource `id` cannot contain hyphens (interpreted as subtraction in CEL) or underscores
- `kind` must be UpperCamelCase/PascalCase (e.g., `WebPlatform`, `MyApp`)
- `apiVersion` must match pattern `v[0-9]+(alpha|beta)?[0-9]*` (e.g., `v1`, `v1alpha1`, `v1beta2`)
- Resource IDs must be unique within an RGD (no duplicates)
- Iterator names in `forEach` must also be lowerCamelCase and unique within that resource
- Iterator names cannot conflict with resource IDs

### Reserved Keywords (Cannot Use as Resource IDs)

CEL reserved: `true`, `false`, `null`, `in`, `as`, `break`, `const`, `continue`, `else`, `for`, `function`, `if`, `import`, `let`, `loop`, `package`, `namespace`, `return`, `var`, `void`, `while`

kro reserved: `schema`, `instance`, `each`, `item`, `items`, `spec`, `status`, `metadata`, `kind`, `apiVersion`, `resources`, `kro`, `self`, `this`, `root`, `context`, `graph`, `runtime`, `version`, `object`, `resource`, `namespace`, `dependency`, `dependencies`, `variables`, `vars`, `externalRef`, `externalReference`, `externalRefs`, `externalReferences`, `resourcegraphdefinition`, `resourceGraphDefinition`, `serviceAccountName`

### Schema Rules

- Nested objects in `spec.schema` default to `{}` if not provided by user
- Status fields MUST reference at least one resource (cannot be pure `schema.spec` expressions)
- Status types are inferred from CEL expression return types
- String templates (multiple `${...}` in one value) require ALL expressions to return strings

### Resource Rules

- Each resource requires `id` + either `template` OR `externalRef` (exactly one)
- Templates must have `apiVersion`, `kind`, and `metadata` fields
- `externalRef.metadata` uses `name` for scalar refs OR `selector` for collection refs (mutually exclusive)
- Scalar externalRef: `metadata.name` (+ optional `namespace`) — fetches one resource
- Collection externalRef: `metadata.selector` with `matchLabels`/`matchExpressions` — fetches array
- `forEach` can be combined with scalar `externalRef` (`metadata.name`) to fan out explicit refs into a collection
- Selector-based externalRef collections use `metadata.selector`, not `forEach`
- `externalRef` namespace defaults to instance namespace if omitted
- `readyWhen` and `includeWhen` can be used with `externalRef`
- Resource field order: `id`, `forEach`, `readyWhen`, `includeWhen`, `template`/`externalRef`

### Expression Constraints

- `includeWhen` can reference `schema.spec` and upstream resources
- Resource-backed `includeWhen` refs participate in dependency inference and cycle detection
- Resource-backed `includeWhen` evaluates against observed upstream state, so it can gate on status as well as spec/data
- If a resource-backed `includeWhen` cannot be decided yet, kro keeps reconciliation pending instead of skipping or failing early
- `readyWhen` can only reference the resource itself by `id` (or `each` for collections, including collection externalRefs)
- `readyWhen` and `includeWhen` must return `bool` or `optional_type(bool)`
- Collections use `each` in `readyWhen`, not the resource id
- forEach iterators cannot reference other iterators (they're independent for cartesian product)
- Circular dependencies between resources, including resource-backed `includeWhen`, are detected and rejected at RGD creation

### Dependency Behavior

- CEL references to other resources create implicit dependencies
- When `includeWhen` is false, all dependent resources (those referencing it via CEL) are also skipped
- Collections are exposed as arrays to other resources (use `map()`, `filter()`, `all()`, etc.), including selector-based and `forEach`-expanded externalRefs
- kro waits for referenced resources to exist before creating dependent resources

### Runtime Behavior

- Managed resources that hit immutable-field apply errors are deleted and recreated automatically
- Immutable recreate only applies to resources already managed by the same kro applyset; unmanaged resources are not recreated automatically
- Recreated resources get a new UID, so downstream systems should not rely on identity stability across immutable updates

### Breaking Changes

- kro blocks breaking schema updates by default: field removal, type changes, new required fields without defaults, enum restrictions, pattern changes
- To allow breaking changes, set `kro.run/allow-breaking-changes: "true"` annotation on the RGD
- Breaking changes are detected at RGD update time, not runtime

### Type Checking

- All CEL expressions are type-checked at RGD creation time (not runtime)
- Expression output types must match target field types
- Structural compatibility: output struct can have fewer fields than expected, but NOT extra fields
- Use `?` operator for fields with unknown structure (ConfigMap data, etc.) - returns null if missing
- Use `.orValue("default")` to provide fallbacks for optional fields
