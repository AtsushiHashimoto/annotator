require 'mongoid'
require 'bcrypt'

class User
	include Mongoid::Document
	
	field :name
	field :email
	field :password_hash
	field :password_salt
	
	attr_readonly :password_hash, :password_salt
	
	validates :name, presence: true
	validates :name, uniqueness: true
	validates :email, uniqueness: true
	validates :email, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\Z/i, on: :create }
	validates :email, presence: true
	validates :password_hash, confirmation: true
	validates :password_hash, presence: true
	validates :password_salt, presence: true
	
	def self.authenticate(email, password)
	user = self.where(email: email).first
	if user && user.password_hash == BCrypt::Engine.hash_secret(password, user.password_salt)
	user
	else
	nil 
end 
end 

def encrypt_password(password)
	if password.present?
		self.password_salt = BCrypt::Engine.generate_salt
		self.password_hash = BCrypt::Engine.hash_secret(password, password_salt)
	end 
end 
end 