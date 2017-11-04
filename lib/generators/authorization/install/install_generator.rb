require 'rails/generators'
module Authorization
  class InstallGenerator < Rails::Generators::Base
    include Rails::Generators::Migration
    source_root File.expand_path('../templates', __FILE__)

    argument :name, type: :string, default: "User"
    argument :attributes, type: :array, default: ['name:string'], banner: "field[:type] field[:type]"
    class_option :create_user, type: :boolean, default: false, desc: "Creates the defined User model with attributes given."
    class_option :commit, type: :boolean, default: false, desc: "Performs rake tasks such as migrate and seed."
    class_option :user_belongs_to_role, type: :boolean, default: false, desc: "Users have only one role, which can inherit others roles."

    def self.next_migration_number(dirname)
      if ActiveRecord::Base.timestamped_migrations
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      else
        "%.3d" % (current_migration_number(dirname) + 1)
      end
    end

    def install_decl_auth
      unless options[:user_belongs_to_role]
        habtm_table_name = if name.pluralize <= "Roles"
                             "#{name.pluralize}Roles"
                           else
                             "Roles#{name.pluralize}"
                           end
        habtm_file_glob = if name.pluralize <= "Roles"
                            'db/migrate/*create_*_roles*'
                          else
                            'db/migrate/*create_roles_*'
                          end
      end

      generate 'model', "#{name} #{attributes.join(' ')}" if options[:create_user]
      generate 'model', 'Role title:string --no-fixture'

      if options[:user_belongs_to_role]
        inject_into_file "app/models/#{name.singularize.downcase}.rb", "  belongs_to :role\n", after: "ActiveRecord::Base\n"
        generate 'migration', "AddRoleIdTo#{name.camelcase} role_id:integer"
      else
        generate 'migration', "Create#{habtm_table_name} #{name.downcase}:integer role:integer"
        gsub_file Dir.glob(habtm_file_glob).last, 'integer', 'references'
        inject_into_file Dir.glob(habtm_file_glob).last, ", id: false", before: ' do |t|'
        inject_into_file "app/models/role.rb", "  has_and_belongs_to_many :#{name.downcase.pluralize}\n", after: "ActiveRecord::Base\n"
        inject_into_file "app/models/#{name.singularize.downcase}.rb", "  has_and_belongs_to_many :roles\n", after: "ActiveRecord::Base\n"
      end

      rake 'db:migrate' if options[:commit]

      if options[:user_belongs_to_role]
        inject_into_file "app/models/#{name.singularize.downcase}.rb", before: "\nend" do
          <<-'RUBY'

  def role_symbols
    [role.title.to_sym]
  end
          RUBY
        end
      else
        inject_into_file "app/models/#{name.singularize.downcase}.rb", before: "\nend" do
          <<-'RUBY'

  def role_symbols
    (roles || []).map {|r| r.title.to_sym}
  end
          RUBY
        end
      end

      inject_into_file 'db/seeds.rb', after: ".first)\n" do
        <<~'RUBY'

          %i(admin user).each do |title|
            Role.find_or_create_by(title: title)
          end
        RUBY
      end

      create_file 'test/fixtures/roles.yaml', <<~RUBY
        admin:
          title: admin

        user:
          title: user
      RUBY

      rake 'db:seed' if options[:commit]

      generate 'authorization:rules'
      puts "Please run `rake db:migrate` and `rake db:seed` to finish installing." unless options[:commit]
    end
  end
end
