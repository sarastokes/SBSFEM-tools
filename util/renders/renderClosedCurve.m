function [binaryMatrix, hiso, boundingBox] = renderClosedCurve(neuron, varargin)
    % RENDERCLOSEDCURVE  3D structure from arbitrary geometry
    %
    % Syntax:
    %   [binaryMatrix, h, boundingBox] = renderClosedCurve(neuron, varargin);
    %
    % Description:
    %   This function renders all closed curve annotations associated with
    %   a neuron. The control points are pulled from OData and smoothed
    %   using a catmull rom spline. The rendering algorithm creates a 3D 
    %   (x,y,z) binary matrix. Closed curve outlines are rendered with the 
    %   patch function in white, cutouts are rendered in black - this 
    %   converts to t/f.
    %
    % Inputs:       
    %   neuron          neuron object
    %
    % Optional key/value pairs:
    %   update      false       fetch neuron geometries
    %   color       gray        FaceColor
    %   alpha       1           FaceAlpha (transparency of render)
    %   sampling    1           Change volume resolution
    %
    % Output: 
    %   binaryMatrix    the binary matrix used to generate the render
    %   h               handle to 3D Patch object
    %
    % See also:
    %   RENDERCLOSEDCURVEOUTLINES
    %
    % History:
    %   9Nov2017 - SSP
    %   29Jul2019 - SSP - Fixed rendering of >1 annotations on one section
    % ---------------------------------------------------------------------

    assert(isa(neuron, 'sbfsem.core.StructureAPI'), 'Input Neuron object');

    % Parse additional inputs
    ip = inputParser();
    ip.CaseSensitive = false;
    addParameter(ip, 'update', false, @islogical);
    addParameter(ip, 'color', [0.7, 0.7, 0.7],...
        @(x) isvector(x) || ischar(x));
    addParameter(ip, 'alpha', 1, @isfloat);
    addParameter(ip, 'sampling', 1, @isnumeric);
    parse(ip, varargin{:});
    faceColor = ip.Results.color;
    faceAlpha = ip.Results.alpha;
    sampling = ip.Results.sampling;
    
    if ischar(faceColor)
        switch faceColor
            case {'l', 'm'}
                faceColor = [.2, 1, 0.4];
            case 's'
                faceColor = [0.2, 0.6, 1];
        end
    end

    % TODO: add return for non-cc objects (prob in setGeometries)
    if ip.Results.update || isempty(neuron.geometries)
        neuron.setGeometries();
    end
    T = neuron.geometries;

    % Convert to ClosedCurve
    Z = [];
    imnodes = cell(0,1);
    for i = 1:height(T)
        imnodes = cat(1, imnodes,...
             sbfsem.builtin.ClosedCurve(T(i,:)));
         Z = cat(1, Z, T.Z(i,:));
    end

    % Find the xy limits to use as bounding box
    fprintf('Calculating bounding box ');
    boundingBox = [ min(imnodes(1).outline(:,1)),...
        max(imnodes(1).outline(:,1)),...
        min(imnodes(1).outline(:,2)),...
        max(imnodes(1).outline(:,2))];
    for i = 2:numel(imnodes)
    	% TODO: optimize this
        if boundingBox(1) > min(imnodes(i).outline(:,1))
            boundingBox(1) = min(imnodes(i).outline(:,1));
        end
        if boundingBox(2) < max(imnodes(i).outline(:,1))
            boundingBox(2) = max(imnodes(i).outline(:,1));
        end
        if boundingBox(3) > min(imnodes(i).outline(:,2))
            boundingBox(3) = min(imnodes(i).outline(:,2));
        end
        if boundingBox(4) < max(imnodes(i).outline(:,2))
            boundingBox(4) = max(imnodes(i).outline(:,2));
        end
    end
    fprintf('= (%u  %u), (%u  %u)\n', round(boundingBox));


    disp('Binarizing closed curves');
    % Get the XY limits
    F = cell(0,1);
    xy = zeros(numel(imnodes), 2);
    for i = 1:numel(imnodes)
    	% Set the bounding box
    	imnodes(i).setBoundingBox(boundingBox);
        % Binarize and downsample
        F = cat(1, F, imnodes(i).resize(sampling));
        % Keep a running count on image sizes
        xy(i,:) = size(imnodes(i).binaryImage);
    end
    % Find the maximum for X and Y dimensions
    xy = max(xy);

    % Resize the binary images to xy limits
    % This usually involves adding a single pixel to the X or Y axis
    binaryMatrix = [];
    for i = 1:numel(imnodes)
        im = F{i};
        if size(im,1) < xy(1)
        	pad = xy(1)-size(im,1);
            im = padarray(im, [pad, 0], 0, 'pre');
        end
        if size(im,2) < xy(2)
        	pad = xy(2)-size(im,2);
            im = padarray(im, [0, pad], 0, 'pre');
        end
        binaryMatrix = cat(3, binaryMatrix, im);
    end
    
    % Combine multiple section annotations
    [zGroups, ~] = findgroups(Z);
    
    binaryMatrix2 = zeros(size(binaryMatrix, 1), size(binaryMatrix, 2), numel(Z));
    for i = numel(Z):-1:1
        binaryMatrix2(:, :, numel(Z)+1-i) = sum(binaryMatrix(:, :, zGroups == i), 3);
    end
    
    hiso = volumeRender(binaryMatrix2,...
        'FaceColor', faceColor,...
        'FaceAlpha', faceAlpha);
    daspect(hiso.Parent, neuron.getDAspect());