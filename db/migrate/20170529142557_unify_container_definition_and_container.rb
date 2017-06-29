class UnifyContainerDefinitionAndContainer < ActiveRecord::Migration[5.0]
  class ContainerDefinition < ActiveRecord::Base
    has_many :container_port_configs, :class_name => 'UnifyContainerDefinitionAndContainer::ContainerPortConfig'
    has_many :container_env_vars, :class_name => 'UnifyContainerDefinitionAndContainer::ContainerEnvVar'
    has_one :security_context, :as => :resource
    has_one :container, :class_name => 'UnifyContainerDefinitionAndContainer::Container'
  end

  class Container < ActiveRecord::Base
    belongs_to :container_definition, :class_name => 'UnifyContainerDefinitionAndContainer::ContainerDefinition'
  end

  class SecurityContext < ActiveRecord::Base
    self.inheritance_column = :_type_disabled
    belongs_to :resource, :polymorphic => true
  end

  class ContainerEnvVar < ActiveRecord::Base
    belongs_to :container_definition, :class_name => 'UnifyContainerDefinitionAndContainer::ContainerDefinition'
  end

  class ContainerPortConfig < ActiveRecord::Base
    belongs_to :container_definition, :class_name => 'UnifyContainerDefinitionAndContainer::ContainerDefinition'
  end

  def up
    # attributes
    add_column :containers, :image,              :string
    add_column :containers, :image_pull_policy,  :string
    add_column :containers, :memory,             :string
    add_column :containers, :cpu_cores,          :float
    add_column :containers, :container_group_id, :bigint
    add_column :containers, :privileged,         :boolean
    add_column :containers, :run_as_user,        :bigint
    add_column :containers, :run_as_non_root,    :boolean
    add_column :containers, :capabilities_add,   :string
    add_column :containers, :capabilities_drop,  :string
    add_column :containers, :command,            :text

    containers = Arel::Table.new(:containers)
    definitions = Arel::Table.new(:container_definitions)
    say_with_time("Copying over columns from container_definition to container") do
      %w(image image_pull_policy memory cpu_cores container_group_id privileged
         run_as_user run_as_non_root capabilities_add capabilities_drop command).each do |column|
        join_sql = definitions.project(definitions[column.to_sym])
                              .where(definitions[:id].eq(containers[:container_definition_id])).to_sql
        Container.update_all("#{column} = (#{join_sql})")
      end
    end

    say_with_time("switch container_definition_id with container_id for container_port_configs") do
      port_configs = Arel::Table.new(:container_port_configs)
      join_sql = containers.project(containers[:id])
                           .where(containers[:container_definition_id].eq(port_configs[:container_definition_id])).to_sql
      ContainerPortConfig.update_all("container_definition_id = (#{join_sql})")
    end

    say_with_time("switch container_definition_id with container_id for container_port_configs") do
      env_vars = Arel::Table.new(:container_env_vars)
      join_sql = containers.project(containers[:id])
                           .where(containers[:container_definition_id].eq(env_vars[:container_definition_id])).to_sql
      ContainerEnvVar.update_all("container_definition_id = (#{join_sql})")
    end

    say_with_time("switch container_definition_id with container_id for security_contexts") do
      security_contexts = Arel::Table.new(:security_contexts)
      join_sql = containers.project(containers[:id])
                           .where(containers[:container_definition_id].eq(security_contexts[:resource_id])
                           .and(security_contexts[:resource_type].eq(Arel::Nodes::Quoted.new('ContainerDefinition')))).to_sql
      SecurityContext.where(:resource_type => 'ContainerDefinition').update_all("resource_type = 'Container', resource_id = (#{join_sql})")
    end

    # relationships
    rename_column :container_port_configs, :container_definition_id, :container_id
    rename_column :container_env_vars, :container_definition_id, :container_id

    remove_column :containers, :container_definition_id
    drop_table :container_definitions
  end

  def down
    create_table :container_definitions do |t|
      t.belongs_to :ems, :type => :bigint
      t.string     :ems_ref
      t.bigint     :old_ems_id
      t.timestamp  :deleted_on
      t.string     :name
      t.string     :image
      t.string     :image_pull_policy
      t.string     :memory
      t.float      :cpu_cores
      t.belongs_to :container_group, :type => :bigint
      t.boolean    :privileged
      t.bigint     :run_as_user
      t.boolean    :run_as_non_root
      t.string     :capabilities_add
      t.string     :capabilities_drop
      t.text       :command
    end

    add_column :containers, :container_definition_id, :bigint

    say_with_time("splitting columns from container into container_definition") do
      ContainerDefinition.transaction do
        Container.all.each do |container|
          container_def = ContainerDefinition.create(
            :ems_id             => container.ems_id,
            :ems_ref            => container.ems_ref,
            :old_ems_id         => container.old_ems_id,
            :deleted_on         => container.deleted_on,
            :name               => container.name,
            :image              => container.image,
            :image_pull_policy  => container.image_pull_policy,
            :memory             => container.memory,
            :cpu_cores          => container.cpu_cores,
            :container_group_id => container.container_group_id,
            :privileged         => container.privileged,
            :run_as_user        => container.run_as_user,
            :run_as_non_root    => container.run_as_non_root,
            :capabilities_add   => container.capabilities_add,
            :capabilities_drop  => container.capabilities_drop,
            :command            => container.command
          )
          container.update!(:container_definition_id => container_def.id)
        end
      end
    end

    containers = Arel::Table.new(:containers)
    say_with_time("switch container_definition_id with container_id for container_port_configs") do
      port_configs = Arel::Table.new(:container_port_configs)
      join_sql = containers.project(containers[:container_definition_id])
                           .where(containers[:id].eq(port_configs[:container_id])).to_sql
      ContainerPortConfig.update_all("container_id = (#{join_sql})")
    end

    say_with_time("switch container_definition_id with container_id for container_port_configs") do
      env_vars = Arel::Table.new(:container_env_vars)
      join_sql = containers.project(containers[:container_definition_id])
                           .where(containers[:id].eq(env_vars[:container_id])).to_sql
      ContainerEnvVar.update_all("container_id = (#{join_sql})")
    end

    say_with_time("switch container_definition_id with container_id for security_contexts") do
      security_contexts = Arel::Table.new(:security_contexts)
      join_sql = containers.project(containers[:container_definition_id])
                           .where(containers[:id].eq(security_contexts[:resource_id])
                           .and(security_contexts[:resource_type].eq(Arel::Nodes::Quoted.new('Container')))).to_sql
      SecurityContext.where(:resource_type => 'Container').update_all("resource_type = 'ContainerDefinition', resource_id = (#{join_sql})")
    end

    # relationships
    rename_column :container_port_configs, :container_id, :container_definition_id
    rename_column :container_env_vars, :container_id, :container_definition_id

    # attributes
    remove_column :containers, :image
    remove_column :containers, :image_pull_policy
    remove_column :containers, :memory
    remove_column :containers, :cpu_cores
    remove_column :containers, :container_group_id
    remove_column :containers, :privileged
    remove_column :containers, :run_as_user
    remove_column :containers, :run_as_non_root
    remove_column :containers, :capabilities_add
    remove_column :containers, :capabilities_drop
    remove_column :containers, :command
  end
end
