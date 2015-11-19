/*
 * Copyright 2012, The Infinite Kind and/or its affiliates. All rights reserved.
 *
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  The Infinite Kind designates this
 * particular file as subject to the "Classpath" exception as provided
 * by The Infinite Kind in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 * 
 */

package com.oracle.appbundler;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

import org.apache.tools.ant.BuildException;


/**
 * Represent a CFBundleDocument.
 */
public class BundleDocument {
    private String name = null;
    private String role = "Editor";
    private String icon = null;
    private String handlerRank = null;
    private List<String> extensions;
    private boolean isPackage = false;

    private String capitalizeFirst(String string) {
        char[] stringArray = string.toCharArray();
        stringArray[0] = Character.toUpperCase(stringArray[0]);
        return new String(stringArray);
    }
    
    public void setExtensions(String extensionsList) {
        if(extensionsList == null) {
            throw new BuildException("Extensions can't be null");
        }
        
        String[] splitedExtensionsList = extensionsList.split(",");
        extensions = new ArrayList<String>();
        
        for (String extension : splitedExtensionsList) {
            String cleanExtension = extension.trim().toLowerCase();
            if (cleanExtension.startsWith(".")) {
                cleanExtension = cleanExtension.substring(1);
            }
            if (cleanExtension.length() > 0) {
                extensions.add(cleanExtension);
            }
        }
        
        if (extensions.size() == 0) {
            throw new BuildException("Extensions list must not be empty");
        }
    }
    
    public void setIcon(String icon) {
      this.icon = icon;
    }

    public void setName(String name) {
      this.name = name;
    }

    public void setRole(String role) {
      this.role = capitalizeFirst(role);
    }
    
    public void setHandlerRank(String handlerRank) {
      this.handlerRank = capitalizeFirst(handlerRank);
    } 
      
    public void setIsPackage(String isPackageString) {
        if(isPackageString.trim().equalsIgnoreCase("true")) {
            this.isPackage = true;
        } else {
            this.isPackage = false;
        }
    }
    
    public String getIcon() {
        return icon;
    }

    public String getName() {
        return name;
    }

    public String getRole() {
        return role;
    }

    public String getHandlerRank() {
        return handlerRank;
    }
    
    public List<String> getExtensions() {
        return extensions;
    }
    
    public File getIconFile() {
        if (icon == null) { return null; }

        File ifile = new File (icon);
        
        if (! ifile.exists ( ) || ifile.isDirectory ( )) { return null; }

        return ifile;
    }
    
    public boolean hasIcon() {
        return icon != null;
    }
    
    public boolean isPackage() {
        return isPackage;
    }

    @Override
    public String toString() {
        StringBuilder s = new StringBuilder(getName());
        s.append(" ").append(getRole()).append(" ").append(getIcon()). append(" ");
        for(String extension : extensions) {
            s.append(extension).append(" ");
        }
        
        return s.toString();
    }
}
