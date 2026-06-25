# .sqlproj Best Practices - Fabric SQL Warehouse

## SDK Configuration

### Correct SDK Version
```xml
<Import Project="$(MSBuildExtensionsPath)\Microsoft.Build.Sql\v0\Microsoft.Build.Sql.props" />
```

**Current Standard**: Microsoft.Build.Sql version 0.1.12-preview

---

## PropertyGroup Settings

### Essential Properties
```xml
<PropertyGroup>
  <Name>ProjectName</Name>
  <ProjectGuid>{UNIQUE-GUID}</ProjectGuid>
  <DSP>Microsoft.Data.Tools.Schema.Sql.SqlDwUnifiedDatabaseSchemaProvider</DSP>
  <ModelCollation>1033, CI</ModelCollation>
  <TargetDatabaseSet>True</TargetDatabaseSet>
</PropertyGroup>
```

### Property Explanations

| Property | Value | Purpose |
|----------|-------|---------|
| DSP | SqlDwUnifiedDatabaseSchemaProvider | Fabric SQL Warehouse compatibility |
| ModelCollation | 1033, CI | Case-insensitive collation |
| TargetDatabaseSet | True | Enables database-level deployment |

---

## SqlCmdVariable Configuration

### Standard Variables
```xml
<ItemGroup>
  <SqlCmdVariable Include="Source_Data">
    <Value>$(SqlCmdVar__1)</Value>
    <DefaultValue>Source_Data</DefaultValue>
  </SqlCmdVariable>

  <SqlCmdVariable Include="ETL_Framework">
    <Value>$(SqlCmdVar__2)</Value>
    <DefaultValue>ETL_Framework</DefaultValue>
  </SqlCmdVariable>

  <SqlCmdVariable Include="Databricks">
    <Value>$(SqlCmdVar__3)</Value>
    <DefaultValue>Databricks</DefaultValue>
  </SqlCmdVariable>
</ItemGroup>
```

### Best Practices
- ✅ DefaultValue must match database name exactly
- ✅ Use consistent naming across all projects
- ✅ Never leave DefaultValue empty
- ✅ Use sequential SqlCmdVar__N numbering

---

## ProjectReference Configuration

### Correct Pattern
```xml
<ItemGroup>
  <ProjectReference Include="..\SourceData\Source_Data\Source_Data.sqlproj">
    <Name>Source_Data</Name>
    <DatabaseSqlCmdVariable>Source_Data</DatabaseSqlCmdVariable>
  </ProjectReference>

  <ProjectReference Include="..\ETL_Framework\ETL_Framework.sqlproj">
    <Name>ETL_Framework</Name>
    <DatabaseSqlCmdVariable>ETL_Framework</DatabaseSqlCmdVariable>
  </ProjectReference>
</ItemGroup>
```

### Best Practices
- ✅ Name must match database name
- ✅ DatabaseSqlCmdVariable must match SqlCmdVariable Include
- ✅ Avoid circular dependencies
- ✅ Keep dependency chain linear (Bronze → Silver → Gold)

---

## PackageReference Configuration

### For Standard Projects
```xml
<ItemGroup>
  <PackageReference Include="Microsoft.SqlServer.Dacpacs.Master">
    <Version>160.0.0</Version>
    <GeneratePathProperty>True</GeneratePathProperty>
    <DatabaseVariableLiteralValue>master</DatabaseVariableLiteralValue>
  </PackageReference>
</ItemGroup>
```

### For ETL Framework
```xml
<ItemGroup>
  <PackageReference Include="Microsoft.SqlServer.Dacpacs.Azure.Master">
    <Version>160.0.0</Version>
    <GeneratePathProperty>True</GeneratePathProperty>
    <DatabaseVariableLiteralValue>master</DatabaseVariableLiteralValue>
  </PackageReference>
</ItemGroup>
```

---

## Build Targets

### BeforeBuild Target
```xml
<Target Name="BeforeBuild">
  <Delete Files="$(BaseIntermediateOutputPath)\project.assets.json" />
</Target>
```

**Purpose**: Prevents NuGet cache issues during build

### Build Exclusions
```xml
<ItemGroup>
  <Build Remove="DW_Developer\ETL\Stored Procedures\usp_Audit_FABRIC_Tables.sql" />
</ItemGroup>
```

---

## Ideal .sqlproj Template

```xml
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Import Project="$(MSBuildExtensionsPath)\Microsoft.Build.Sql\v0\Microsoft.Build.Sql.props" />
  
  <PropertyGroup>
    <Name>ProjectName</Name>
    <ProjectGuid>{UNIQUE-GUID}</ProjectGuid>
    <DSP>Microsoft.Data.Tools.Schema.Sql.SqlDwUnifiedDatabaseSchemaProvider</DSP>
    <ModelCollation>1033, CI</ModelCollation>
    <TargetDatabaseSet>True</TargetDatabaseSet>
  </PropertyGroup>

  <ItemGroup>
    <SqlCmdVariable Include="Source_Data">
      <Value>$(SqlCmdVar__1)</Value>
      <DefaultValue>Source_Data</DefaultValue>
    </SqlCmdVariable>
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\SourceData\Source_Data\Source_Data.sqlproj">
      <Name>Source_Data</Name>
      <DatabaseSqlCmdVariable>Source_Data</DatabaseSqlCmdVariable>
    </ProjectReference>
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.SqlServer.Dacpacs.Master">
      <Version>160.0.0</Version>
      <GeneratePathProperty>True</GeneratePathProperty>
      <DatabaseVariableLiteralValue>master</DatabaseVariableLiteralValue>
    </PackageReference>
  </ItemGroup>

  <Target Name="BeforeBuild">
    <Delete Files="$(BaseIntermediateOutputPath)\project.assets.json" />
  </Target>

  <Import Project="$(MSBuildExtensionsPath)\Microsoft.Build.Sql\v0\Microsoft.Build.Sql.targets" />
</Project>
```

---

## Fabric-Specific Considerations

### Supported Features
- ✅ Tables (heap, clustered columnstore)
- ✅ Views
- ✅ Stored Procedures
- ✅ Functions
- ✅ Schemas
- ✅ Indexes
- ✅ Statistics

### Unsupported Features
- ❌ Filegroups
- ❌ Partitioning schemes
- ❌ Full-text search
- ❌ Replication
- ❌ Service Broker
- ❌ Temporal tables

---

## Validation Checklist

- [ ] DSP is SqlDwUnifiedDatabaseSchemaProvider
- [ ] ModelCollation is 1033, CI
- [ ] All SqlCmdVariables have DefaultValues
- [ ] DefaultValues match database names
- [ ] ProjectReferences have DatabaseSqlCmdVariable
- [ ] No circular dependencies
- [ ] BeforeBuild target present
- [ ] PackageReference version is 160.0.0
- [ ] No unsupported Fabric features
- [ ] Builds successfully locally

---

**Last Updated**: October 21, 2025  
**Version**: 1.0

