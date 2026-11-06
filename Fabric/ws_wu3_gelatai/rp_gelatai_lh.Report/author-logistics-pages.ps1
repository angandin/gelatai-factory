[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$reportRoot = $PSScriptRoot
$pagesRoot = Join-Path $reportRoot 'definition\pages'
$schema = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.10.0/schema.json'

function New-Literal {
    param([Parameter(Mandatory)][string] $Value)
    @{ expr = @{ Literal = @{ Value = $Value } } }
}

function New-Color {
    param([Parameter(Mandatory)][string] $Hex)
    @{ solid = @{ color = New-Literal -Value "'$Hex'" } }
}

function New-ColumnProjection {
    param(
        [Parameter(Mandatory)][string] $Table,
        [Parameter(Mandatory)][string] $Column
    )
    @{
        field = @{
            Column = @{
                Expression = @{ SourceRef = @{ Entity = $Table } }
                Property = $Column
            }
        }
        queryRef = "$Table.$Column"
        nativeQueryRef = $Column
    }
}

function New-MeasureProjection {
    param(
        [Parameter(Mandatory)][string] $Table,
        [Parameter(Mandatory)][string] $Measure
    )
    @{
        field = @{
            Measure = @{
                Expression = @{ SourceRef = @{ Entity = $Table } }
                Property = $Measure
            }
        }
        queryRef = "$Table.$Measure"
        nativeQueryRef = $Measure
    }
}

function New-Position {
    param(
        [int] $X, [int] $Y, [int] $Width, [int] $Height, [int] $Order
    )
    @{ x = $X; y = $Y; z = $Order; width = $Width; height = $Height; tabOrder = $Order }
}

function New-ContainerObjects {
    param([Parameter(Mandatory)][string] $Title)
    @{
        title = @(
            @{
                properties = @{
                    show = New-Literal -Value 'true'
                    text = New-Literal -Value "'$Title'"
                    heading = New-Literal -Value "'Heading3'"
                    fontColor = New-Color -Hex '#17324D'
                    fontSize = New-Literal -Value '12D'
                    bold = New-Literal -Value 'true'
                }
            }
        )
        background = @(
            @{
                properties = @{
                    show = New-Literal -Value 'true'
                    color = New-Color -Hex '#FFFFFF'
                    transparency = New-Literal -Value '0D'
                }
            }
        )
        border = @(
            @{
                properties = @{
                    show = New-Literal -Value 'true'
                    color = New-Color -Hex '#D9E2EA'
                    radius = New-Literal -Value '8D'
                    width = New-Literal -Value '1D'
                }
            }
        )
    }
}

function New-TextBox {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $Subtitle,
        [Parameter(Mandatory)][hashtable] $Position
    )
    @{
        '$schema' = $schema
        name = $Name
        position = $Position
        visual = @{
            visualType = 'textbox'
            objects = @{
                general = @(
                    @{
                        properties = @{
                            paragraphs = @(
                                @{
                                    textRuns = @(
                                        @{
                                            value = $Title
                                            textStyle = @{
                                                fontFamily = 'Segoe UI Semibold'
                                                fontSize = '21pt'
                                                foreground = '#17324D'
                                            }
                                        }
                                    )
                                },
                                @{
                                    textRuns = @(
                                        @{
                                            value = $Subtitle
                                            textStyle = @{
                                                fontFamily = 'Segoe UI'
                                                fontSize = '9pt'
                                                foreground = '#587083'
                                            }
                                        }
                                    )
                                }
                            )
                        }
                    }
                )
            }
            drillFilterOtherVisuals = $true
        }
    }
}

function New-Slicer {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Table,
        [Parameter(Mandatory)][string] $Column,
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][hashtable] $Position
    )
    @{
        '$schema' = $schema
        name = $Name
        position = $Position
        visual = @{
            visualType = 'slicer'
            query = @{
                queryState = @{
                    Values = @{
                        projections = @(New-ColumnProjection -Table $Table -Column $Column)
                    }
                }
            }
            objects = @{
                data = @(@{ properties = @{ mode = New-Literal -Value "'Dropdown'" } })
                header = @(
                    @{
                        properties = @{
                            show = New-Literal -Value 'true'
                            text = New-Literal -Value "'$Label'"
                        }
                    }
                )
            }
            visualContainerObjects = @{
                padding = @(
                    @{
                        properties = @{
                            top = New-Literal -Value '8D'
                            bottom = New-Literal -Value '8D'
                            left = New-Literal -Value '8D'
                            right = New-Literal -Value '8D'
                        }
                    }
                )
                background = @(
                    @{
                        properties = @{
                            show = New-Literal -Value 'true'
                            color = New-Color -Hex '#FFFFFF'
                            transparency = New-Literal -Value '0D'
                        }
                    }
                )
                border = @(
                    @{
                        properties = @{
                            show = New-Literal -Value 'true'
                            color = New-Color -Hex '#C9D5DE'
                            radius = New-Literal -Value '8D'
                            width = New-Literal -Value '1D'
                        }
                    }
                )
            }
            drillFilterOtherVisuals = $true
        }
    }
}

function New-CardStrip {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][array] $Measures,
        [Parameter(Mandatory)][hashtable] $Position
    )
    $projections = foreach ($measure in $Measures) {
        New-MeasureProjection -Table $measure.Table -Measure $measure.Measure
    }
    @{
        '$schema' = $schema
        name = $Name
        position = $Position
        visual = @{
            visualType = 'cardVisual'
            query = @{ queryState = @{ Data = @{ projections = @($projections) } } }
            objects = @{
                outline = @(
                    @{
                        properties = @{ show = New-Literal -Value 'false' }
                        selector = @{ id = 'default' }
                    }
                )
                value = @(
                    @{
                        properties = @{
                            fontSize = New-Literal -Value '20D'
                            fontColor = New-Color -Hex '#17324D'
                        }
                        selector = @{ id = 'default' }
                    }
                )
                label = @(
                    @{
                        properties = @{
                            show = New-Literal -Value 'true'
                            fontSize = New-Literal -Value '9D'
                            fontColor = New-Color -Hex '#587083'
                        }
                        selector = @{ id = 'default' }
                    }
                )
            }
            visualContainerObjects = @{
                background = @(
                    @{
                        properties = @{
                            show = New-Literal -Value 'true'
                            color = New-Color -Hex '#FFFFFF'
                            transparency = New-Literal -Value '0D'
                        }
                    }
                )
                border = @(
                    @{
                        properties = @{
                            show = New-Literal -Value 'true'
                            color = New-Color -Hex '#D9E2EA'
                            radius = New-Literal -Value '8D'
                            width = New-Literal -Value '1D'
                        }
                    }
                )
            }
            drillFilterOtherVisuals = $true
        }
    }
}

function New-BarChart {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $CategoryTable,
        [Parameter(Mandatory)][string] $CategoryColumn,
        [Parameter(Mandatory)][string] $MeasureTable,
        [Parameter(Mandatory)][string] $Measure,
        [Parameter(Mandatory)][string] $Color,
        [Parameter(Mandatory)][hashtable] $Position
    )
    $measureExpression = @{
        Measure = @{
            Expression = @{ SourceRef = @{ Entity = $MeasureTable } }
            Property = $Measure
        }
    }
    @{
        '$schema' = $schema
        name = $Name
        position = $Position
        visual = @{
            visualType = 'clusteredBarChart'
            query = @{
                queryState = @{
                    Category = @{
                        projections = @(New-ColumnProjection -Table $CategoryTable -Column $CategoryColumn)
                    }
                    Y = @{
                        projections = @(New-MeasureProjection -Table $MeasureTable -Measure $Measure)
                    }
                }
                sortDefinition = @{
                    sort = @(
                        @{
                            field = $measureExpression
                            direction = 'Descending'
                        }
                    )
                }
            }
            objects = @{
                categoryAxis = @(
                    @{ properties = @{ axisType = New-Literal -Value "'Categorical'" } }
                )
                labels = @(
                    @{
                        properties = @{
                            show = New-Literal -Value 'true'
                            color = New-Color -Hex '#17324D'
                        }
                    }
                )
                dataPoint = @(
                    @{ properties = @{ fill = New-Color -Hex $Color } }
                )
            }
            visualContainerObjects = New-ContainerObjects -Title $Title
            drillFilterOtherVisuals = $true
        }
    }
}

function New-TableVisual {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][array] $Fields,
        [Parameter(Mandatory)][hashtable] $Position
    )
    $projections = foreach ($field in $Fields) {
        if ($field.Kind -eq 'Measure') {
            New-MeasureProjection -Table $field.Table -Measure $field.Property
        } else {
            New-ColumnProjection -Table $field.Table -Column $field.Property
        }
    }
    @{
        '$schema' = $schema
        name = $Name
        position = $Position
        visual = @{
            visualType = 'tableEx'
            query = @{ queryState = @{ Values = @{ projections = @($projections) } } }
            objects = @{
                columnHeaders = @(
                    @{
                        properties = @{
                            columnAdjustment = New-Literal -Value "'growToFit'"
                            autoSizeColumnWidth = New-Literal -Value 'true'
                            backColor = New-Color -Hex '#EAF1F5'
                            fontColor = New-Color -Hex '#17324D'
                        }
                    }
                )
                values = @(
                    @{
                        properties = @{
                            backColorPrimary = New-Color -Hex '#FFFFFF'
                            backColorSecondary = New-Color -Hex '#F5F8FA'
                            fontColorPrimary = New-Color -Hex '#243746'
                            fontColorSecondary = New-Color -Hex '#243746'
                        }
                    }
                )
            }
            visualContainerObjects = New-ContainerObjects -Title $Title
            drillFilterOtherVisuals = $true
        }
    }
}

function Write-Page {
    param(
        [Parameter(Mandatory)][string] $PageName,
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][array] $Visuals
    )
    $pageRoot = Join-Path $pagesRoot $PageName
    if (Test-Path $pageRoot) {
        Remove-Item -LiteralPath $pageRoot -Recurse -Force
    }
    $visualsRoot = Join-Path $pageRoot 'visuals'
    $null = New-Item -ItemType Directory -Path $visualsRoot -Force

    $page = [ordered]@{
        '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json'
        name = $PageName
        displayName = $DisplayName
        displayOption = 'FitToPage'
        height = 720
        width = 1280
    }
    $page | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $pageRoot 'page.json') -Encoding utf8

    foreach ($visual in $Visuals) {
        $visualRoot = Join-Path $visualsRoot $visual.name
        $null = New-Item -ItemType Directory -Path $visualRoot -Force
        $visual | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $visualRoot 'visual.json') -Encoding utf8
    }
}

$distributionPage = '6a1f9c8b2d4e7a0135bc'
$assortmentPage = '7b2e0d9c3f5a8b1246de'

$distributionVisuals = @(
    (New-TextBox -Name 'a0000000000000000001' -Title 'Distribution overview' -Subtitle 'Factory-to-shop product flow, receiving progress, and destination performance' -Position (New-Position 20 10 780 64 1000)),
    (New-Slicer -Name 'a0000000000000000002' -Table 'Shop' -Column 'Shop Name' -Label 'Shop' -Position (New-Position 864 8 184 80 2000)),
    (New-Slicer -Name 'a0000000000000000003' -Table 'Shipment' -Column 'Dispatch Date' -Label 'Dispatch date' -Position (New-Position 1064 8 196 80 3000)),
    (New-CardStrip -Name 'a0000000000000000004' -Measures @(
        @{ Table = 'Shipment Flow'; Measure = 'Total Items Shipped' },
        @{ Table = 'Shipment Flow'; Measure = 'Total Items Received' },
        @{ Table = 'Shipment Flow'; Measure = 'Receipt Rate' },
        @{ Table = 'Shipment Flow'; Measure = 'Shipments' },
        @{ Table = 'Shipment Flow'; Measure = 'Shops Served' }
    ) -Position (New-Position 20 92 1240 112 4000)),
    (New-BarChart -Name 'a0000000000000000005' -Title 'Items shipped by shop' -CategoryTable 'Shop' -CategoryColumn 'Shop Name' -MeasureTable 'Shipment Flow' -Measure 'Total Items Shipped' -Color '#1F6F8B' -Position (New-Position 20 220 752 480 5000)),
    (New-BarChart -Name 'a0000000000000000006' -Title 'Shipments by status' -CategoryTable 'Shipment' -CategoryColumn 'Shipment Status' -MeasureTable 'Shipment Flow' -Measure 'Shipments' -Color '#2A9D8F' -Position (New-Position 788 220 472 220 6000)),
    (New-TableVisual -Name 'a0000000000000000007' -Title 'Shipment detail' -Fields @(
        @{ Kind = 'Column'; Table = 'Shipment'; Property = 'Shipment Number' },
        @{ Kind = 'Column'; Table = 'Shipment'; Property = 'Dispatch Date' },
        @{ Kind = 'Column'; Table = 'Shop'; Property = 'Shop Name' },
        @{ Kind = 'Measure'; Table = 'Shipment Flow'; Property = 'Total Items Shipped' },
        @{ Kind = 'Measure'; Table = 'Shipment Flow'; Property = 'Receipt Rate' }
    ) -Position (New-Position 788 456 472 244 7000))
)

$assortmentVisuals = @(
    (New-TextBox -Name 'b0000000000000000001' -Title 'Shop assortment' -Subtitle 'Product availability, featured flavors, stock position, and replenishment exceptions' -Position (New-Position 20 10 780 64 1000)),
    (New-Slicer -Name 'b0000000000000000002' -Table 'Shop' -Column 'Shop Name' -Label 'Shop' -Position (New-Position 864 8 184 80 2000)),
    (New-Slicer -Name 'b0000000000000000003' -Table 'Product' -Column 'Category' -Label 'Product category' -Position (New-Position 1064 8 196 80 3000)),
    (New-CardStrip -Name 'b0000000000000000004' -Measures @(
        @{ Table = 'Shop Availability'; Measure = 'Available Products' },
        @{ Table = 'Shop Availability'; Measure = 'Featured Products' },
        @{ Table = 'Shop Availability'; Measure = 'Inventory Units' },
        @{ Table = 'Shop Availability'; Measure = 'Items Needing Reorder' },
        @{ Table = 'Shop Availability'; Measure = 'Assortment Coverage' }
    ) -Position (New-Position 20 92 1240 112 4000)),
    (New-BarChart -Name 'b0000000000000000005' -Title 'Available products by shop' -CategoryTable 'Shop' -CategoryColumn 'Shop Name' -MeasureTable 'Shop Availability' -Measure 'Available Products' -Color '#1F6F8B' -Position (New-Position 20 220 610 248 5000)),
    (New-BarChart -Name 'b0000000000000000006' -Title 'Shop coverage by product' -CategoryTable 'Product' -CategoryColumn 'Product Name' -MeasureTable 'Shop Availability' -Measure 'Shops with Availability' -Color '#2A9D8F' -Position (New-Position 650 220 610 248 6000)),
    (New-TableVisual -Name 'b0000000000000000007' -Title 'Shop and product availability detail' -Fields @(
        @{ Kind = 'Column'; Table = 'Shop'; Property = 'Shop Name' },
        @{ Kind = 'Column'; Table = 'Product'; Property = 'Product Name' },
        @{ Kind = 'Column'; Table = 'Product'; Property = 'Category' },
        @{ Kind = 'Column'; Table = 'Shop Availability'; Property = 'Is Featured' },
        @{ Kind = 'Measure'; Table = 'Shop Availability'; Property = 'Inventory Units' },
        @{ Kind = 'Measure'; Table = 'Inventory'; Property = 'Needs Reorder' }
    ) -Position (New-Position 20 484 1240 216 7000))
)

Write-Page -PageName $distributionPage -DisplayName 'Distribution Overview' -Visuals $distributionVisuals
Write-Page -PageName $assortmentPage -DisplayName 'Shop Assortment' -Visuals $assortmentVisuals

$telemetryPagePath = Join-Path $pagesRoot '261de73c83da71d0c100\page.json'
$telemetryPage = Get-Content -LiteralPath $telemetryPagePath -Raw | ConvertFrom-Json
$telemetryPage.displayName = 'Factory Telemetry'
$telemetryPage | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $telemetryPagePath -Encoding utf8

$telemetryVisualsRoot = Join-Path $pagesRoot '261de73c83da71d0c100\visuals'
$summaryVisualRoot = Join-Path $telemetryVisualsRoot '1a6d9ca75b03cb84a389'
if (Test-Path $summaryVisualRoot) {
    Remove-Item -LiteralPath $summaryVisualRoot -Recurse -Force
}
foreach ($heightUpdate in @(
    @{ Name = '6d029e3873a6aa35e7da'; Height = 40 },
    @{ Name = 'e586dc2eed53b7937cdc'; Height = 48 }
)) {
    $visualPath = Join-Path $telemetryVisualsRoot "$($heightUpdate.Name)\visual.json"
    $visual = Get-Content -LiteralPath $visualPath -Raw | ConvertFrom-Json
    $visual.position.height = $heightUpdate.Height
    $visual | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $visualPath -Encoding utf8
}

$pagesMetadataPath = Join-Path $pagesRoot 'pages.json'
$pagesMetadata = Get-Content -LiteralPath $pagesMetadataPath -Raw | ConvertFrom-Json
$pagesMetadata.pageOrder = @($distributionPage, $assortmentPage, '261de73c83da71d0c100')
$pagesMetadata.activePageName = $distributionPage
$pagesMetadata | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $pagesMetadataPath -Encoding utf8

Write-Host 'Authored Distribution Overview and Shop Assortment pages.'
