# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "92e59539-b5cf-4ae0-babe-fa481abc416d",
# META       "default_lakehouse_name": "GelatAI_lakehouse",
# META       "default_lakehouse_workspace_id": "97d5eec3-d6d9-44bb-80aa-279e286309b3",
# META       "known_lakehouses": [
# META         {
# META           "id": "92e59539-b5cf-4ae0-babe-fa481abc416d"
# META         }
# META       ]
# META     }
# META   }
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC CREATE OR REPLACE TABLE dbo.Manuals_MachineIssues (
# MAGIC   machine_type STRING NOT NULL,
# MAGIC   manual       STRING NOT NULL
# MAGIC ) USING DELTA;
# MAGIC 
# MAGIC INSERT INTO dbo.Manuals_MachineIssues (machine_type, manual) VALUES
# MAGIC   ('scale',           'machineissues'),
# MAGIC   ('mixer',           'machineissues'),
# MAGIC   ('mix_cooker',      'machineissues'),
# MAGIC   ('pasteurizer',     'machineissues'),
# MAGIC   ('homogenizer',     'machineissues'),
# MAGIC   ('aging_tank',      'machineissues'),
# MAGIC   ('blast_freezer',   'machineissues'),
# MAGIC   ('storage_freezer', 'machineissues'),
# MAGIC   ('cold_room',       'machineissues'),
# MAGIC   ('batch_freezer',   'machineissues');

# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC CREATE OR REPLACE TABLE dbo.Manuals_FactoryHowWork (
# MAGIC   factory_id INT NOT NULL,
# MAGIC   manual       STRING NOT NULL
# MAGIC ) USING DELTA;
# MAGIC 
# MAGIC INSERT INTO dbo.Manuals_FactoryHowWork (factory_id, manual) VALUES
# MAGIC   ('gelatai-factory-001',           'factoryhowworks');

# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC CREATE OR REPLACE TABLE dbo.Manuals (
# MAGIC   manual       STRING NOT NULL,
# MAGIC   index_name   STRING NOT NULL
# MAGIC ) USING DELTA;
# MAGIC 
# MAGIC INSERT INTO dbo.Manuals (manual, index_name) VALUES
# MAGIC   ('machineissues', 'machines-anomaly-manual'),
# MAGIC   ('factoryhowworks', 'factory-functional');

# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }
