# Provides authentication features. Based closely on RESTful Authentication
# by Rick Olson (as attributed below).
#
# Author::      Eli Fox-Epstein, efoxepstein@wesleyan.edu
# Author::      Dimitar Gochev, dimitar.gochev@trincoll.edu
# Copyright::   Humanitarian FOSS Project (http://www.hfoss.org), Copyright (C) 2009.
# License::     http://www.gnu.org/copyleft/lesser.html GNU Lesser General Public License (LGPL)

# Copyright (c) 2009 Rick Olson
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module Auth
  protected
  
    # For use in <tt>return with_rejection unless ... </tt>. Options include:
    # * :error, the error message to display
    # * :fail_to, the page to render
    def with_rejection(opts = {})
      opts[:error] ||= "You are not authorized to view that page."
      if request.env["HTTP_REFERER"]
        opts[:fail_to] ||= :back
      else
        opts[:fail_to] ||= {:controller => :instances, :action => :show, :id => @instance.to_param}
      end
      error_exit(opts[:fail_to], opts[:error])
    end

    # Sets flash[:error] to error and redirects to exit
    def error_exit(exit, error = "You are not authorized to view that page.")
      flash[:error] = error
      redirect_to exit
    end
    
    def notice_exit(exit, notice)
      flash[:notice] = notice
      redirect_to exit
    end
    
    # Redirects to the login path unless the user is logged in
    def require_login
      @current_user = nil
      path = instance_login_path(Instance.find(params[:instance_id]||params[:id]), :return_to => request.request_uri)
      notice = "You must be logged in to view this page."
      notice_exit(path, notice) unless logged_in?
    end
    
    def require_admin_login
      notice = "You must be logged in to view this page."
      notice_exit(login_path, notice) unless logged_in?(:admin)
    end  
  
    # Returns true if the user is logged in. Will try to log in from session and cookie.
    def logged_in?(as = :user)
      if as == :user
        login
        !!@current_user 
      elsif as == :admin
        login_from_session
        !!Admin.current
      end
    end

    # Inclusion hook to make #current_user and #logged_in?
    # available as ActionView helper methods.
    def self.included(base)
      base.send :helper_method, :logged_in? if base.respond_to? :helper_method
    end
    
    # Logs in as a user. Just sets the session, not any cookies.
    def login_as(user, type = :user)
      session["#{type}_id".to_sym] = user ? user.id : nil
      if user.is_a? User
        user.last_login = DateTime.now
        user.save
      end
      if type == :user || user.is_a?(User)
        @current_user = user
      elsif type == :admin || user.is_a?(Admin)
        Admin.current = user
      end
    end
    
    # Tries to log in from session or cookie
    def login
      login_from_session || login_from_cookie
    end

    # Tries to log in from session
    def login_from_session
      login_as User.find(session[:user_id]) if session[:user_id]
      login_as Admin.find(session[:admin_id]), :admin if session[:admin_id]
    end

    # Tries to log in from cookie
    def login_from_cookie
      user = cookies[:auth_token] && User.find_by_remember_token(cookies[:auth_token])
      if user && user.remember_token?
        login_as user
        handle_remember_cookie! false # freshen cookie token (keeping date)
        @current_user
      end
    end

    # Logs out without destroying the session so the CSRF protection isn't wrecked.
    def logout_keeping_session!
      if @current_user.is_a? User
        @current_user.last_logout = DateTime.now
        @current_user.save
        @current_user.forget_me
      end
      login_as false
      kill_remember_cookie!     # Kill client-side auth cookie
      session[:user_id] = nil   # keeps the session but kill our variable
      session[:admin_id] = nil
    end

    # Does a complete log out including destroying the session.
    def logout_killing_session!
      logout_keeping_session!
      reset_session
    end

    # Returns whether the remember cookie is valid for the logged-in user
    def valid_remember_cookie?
      return nil unless @current_user
      (@current_user.remember_token?) && 
        (cookies[:auth_token] == @current_user.remember_token)
    end
    
    # Refresh the cookie auth token if it exists, create it otherwise
    def handle_remember_cookie!(new_cookie_flag)
      return unless @current_user
      
      if valid_remember_cookie?
        @current_user.refresh_token # keep same expiration date
      elsif new_cookie_flag
        @current_user.remember_me 
      else
        @current_user.forget_me
      end
      
      send_remember_cookie!
    end
  
    # Deletes remember cookie
    def kill_remember_cookie!
      cookies.delete :auth_token
    end
    
    # Sets remember cookie
    def send_remember_cookie!
      cookies[:auth_token] = {
        :value   => @current_user.remember_token,
        :expires => @current_user.remember_token_expires_at }
    end

end
